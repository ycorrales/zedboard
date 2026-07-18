#include <linux/delay.h>
#include <linux/device.h>
#include <linux/err.h>
#include <linux/fs.h>
#include <linux/gpio/consumer.h>
#include <linux/kernel.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/string.h>
#include <linux/uaccess.h>
#include <linux/version.h>

#define DEVICE_NAME "zed_oled"

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 11, 0)
#define REMOVE_RET_TYPE void
#else
#define REMOVE_RET_TYPE int
#endif

static int major_num;
static struct class *oled_class;
static struct device *oled_device;

/* Internal geometry trackers */
static bool flip_x = true;
static bool flip_y = true;

/* GPIO descriptors resolved from DT. Logical values honor GPIO_ACTIVE_* flags. */
static struct gpio_desc *gpio_dc;
static struct gpio_desc *gpio_res;
static struct gpio_desc *gpio_sclk;
static struct gpio_desc *gpio_sdin;
static struct gpio_desc *gpio_vbat;
static struct gpio_desc *gpio_vdd;

/* Core SSD1306 init sequence (128x32, 1/32 duty) */
static unsigned char init_sequence[] = {
    0xAE,        // Display off
    0xD5, 0x80,  // Clock divide ratio
    0xA8, 0x1F,  // Multiplex ratio (1/32)
    0xD3, 0x00,  // Display offset 0
    0x40,        // Start line 0
    0x8D, 0x14,  // Charge pump enable
    0xA0,        // Set segment re-map (Overwritten dynamically in probe) (0xA1 flip X-axis)
    0xC8,        // COM scan direction (Overwritten dynamically in probe) (0xC8 flip Y-axis)
    0xDA, 0x02,  // COM pins config
    0x81, 0x7F,  // Contrast
    0xD9, 0xF1,  // Pre-charge period
    0xDB, 0x40,  // VCOMH deselect
    0xA4,        // Resume to RAM content
    0xA6,        // Normal display
    0xAF         // Display on
};

static void oled_bitbang_byte(u8 data)
{
  int i;
  for (i = 7; i >= 0; i--)
  {
    gpiod_set_value_cansleep(gpio_sclk, 0);
    gpiod_set_value_cansleep(gpio_sdin, (data & (1 << i)) ? 1 : 0);
    udelay(1);

    gpiod_set_value_cansleep(gpio_sclk, 1);
    udelay(1);
  }
  gpiod_set_value_cansleep(gpio_sclk, 0); /* leave clock low */
}

static void oled_send_command(u8 cmd)
{
  gpiod_set_value_cansleep(gpio_dc, 0); /* command mode */
  oled_bitbang_byte(cmd);
}

static void oled_initialize(void)
{
  int i;

  gpiod_set_value_cansleep(gpio_vdd, 1); /* VDD ON */
  msleep(1);

  gpiod_set_value_cansleep(gpio_res, 1); /* reset assert */
  msleep(10);
  gpiod_set_value_cansleep(gpio_res, 0); /* reset release */

  oled_send_command(0xAE);
  gpiod_set_value_cansleep(gpio_vbat, 1); /* VBAT ON */
  msleep(100);

  for (i = 0; i < sizeof(init_sequence); i++)
    oled_send_command(init_sequence[i]);
}

/*
 * Runtime Custom Callback Handler:
 * Re-configures indices 10 and 11 and uploads directly to panel when sysfs changes.
 */
static int notify_param_set(const char *val, const struct kernel_param *kp)
{
  int ret;

  /* Standard bool processing helper ("1", "0", "Y", "N", etc.) */
  ret = param_set_bool(val, kp);
  if (ret < 0)
    return ret;

  /* Ensure we don't issue commands if GPIOs aren't probed yet */
  if (!gpio_dc || !gpio_sclk || !gpio_sdin)
    return 0;

  pr_info("zed_oled: Runtime geometry change detected! Re-programming hardware.\n");

  /* Update our array mappings safely using indices 10 and 11 */
  init_sequence[10] = flip_x ? 0xA1 : 0xA0;
  init_sequence[11] = flip_y ? 0xC0 : 0xC8;

  /* Instantly send only the configuration shift commands to the live panel */
  oled_send_command(init_sequence[10]);
  oled_send_command(init_sequence[11]);

  return 0;
}

/* Link custom set with standard bool read function */
static const struct kernel_param_ops geometry_param_ops = {
    .set = notify_param_set,
    .get = param_get_bool,
};

/* Register parameters using module_param_cb with 0644 Permissions */
module_param_cb(flip_x, &geometry_param_ops, &flip_x, 0644);
MODULE_PARM_DESC(flip_x, "Flip horizontal X-axis: 0 = Normal, 1 = Flipped");

module_param_cb(flip_y, &geometry_param_ops, &flip_y, 0644);
MODULE_PARM_DESC(flip_y, "Flip vertical Y-axis: 0 = Normal, 1 = Flipped");

static ssize_t oled_write(struct file *file, const char __user *buffer,
                          size_t len, loff_t *offset)
{
  u8 page, col;
  u8 kbuf[512];

  if (len > 512) len = 512;
  memset(kbuf, 0, 512);
  if (copy_from_user(kbuf, buffer, len)) return -EFAULT;

  for (page = 0; page < 4; page++)
  {
    oled_send_command(0xB0 + page);
    oled_send_command(0x00);
    oled_send_command(0x10);

    gpiod_set_value_cansleep(gpio_dc, 1); /* data mode */
    for (col = 0; col < 128; col++)
      oled_bitbang_byte(kbuf[page * 128 + col]);
  }
  return len;
}

static struct file_operations fops = {
    .owner = THIS_MODULE,
    .write = oled_write,
};

/* devnode callback: set /dev/zed_oled to 0660 (rw-rw----) */
static char *oled_devnode(const struct device *dev, umode_t *mode)
{
  if (mode)
    *mode = 0660;
  return NULL;
}

/* Helper: request a named GPIO as logical-low output. */
static int oled_get_gpio(struct device *dev, const char *name,
                         struct gpio_desc **gpio_out)
{
  struct gpio_desc *gpio;

  gpio = devm_gpiod_get(dev, name, GPIOD_OUT_LOW);
  if (IS_ERR(gpio))
  {
    dev_err(dev, "Failed to request %s-gpios from DT (%ld)\n",
            name, PTR_ERR(gpio));
    return PTR_ERR(gpio);
  }

  *gpio_out = gpio;
  return 0;
}

static int zed_oled_probe(struct platform_device *pdev)
{
  struct device *dev = &pdev->dev;
  int ret;

  /* Synchronize physical layout constraints defined at initial startup loading */
  init_sequence[10] = flip_x ? 0xA1 : 0xA0;
  init_sequence[11] = flip_y ? 0xC0 : 0xC8;

  ret = oled_get_gpio(dev, "dc", &gpio_dc);
  if (ret) return ret;
  ret = oled_get_gpio(dev, "reset", &gpio_res);
  if (ret) return ret;
  ret = oled_get_gpio(dev, "sclk", &gpio_sclk);
  if (ret) return ret;
  ret = oled_get_gpio(dev, "data", &gpio_sdin);
  if (ret) return ret;
  ret = oled_get_gpio(dev, "vbat", &gpio_vbat);
  if (ret) return ret;
  ret = oled_get_gpio(dev, "vdd", &gpio_vdd);
  if (ret) return ret;

  oled_initialize();

  /* Register char device */
  major_num = register_chrdev(0, DEVICE_NAME, &fops);
  if (major_num < 0)
  {
    return major_num;
  }

  oled_class = class_create(DEVICE_NAME);
  if (IS_ERR(oled_class))
  {
    ret = PTR_ERR(oled_class);
    goto err_chrdev;
  }

  oled_class->devnode = oled_devnode;
  oled_device = device_create(oled_class, NULL, MKDEV(major_num, 0),
                              NULL, DEVICE_NAME);
  if (IS_ERR(oled_device))
  {
    ret = PTR_ERR(oled_device);
    goto err_class;
  }

  dev_info(dev, "ZedBoard OLED EMIO Driver Initialized (/dev/%s)\n", DEVICE_NAME);
  return 0;

err_class:
  class_destroy(oled_class);
err_chrdev:
  unregister_chrdev(major_num, DEVICE_NAME);
  return ret;
}

static REMOVE_RET_TYPE zed_oled_remove(struct platform_device *pdev)
{
  /* Power down display safely */
  oled_send_command(0xAE);
  gpiod_set_value_cansleep(gpio_vbat, 0);
  msleep(100);
  gpiod_set_value_cansleep(gpio_vdd, 0);

  device_destroy(oled_class, MKDEV(major_num, 0));
  class_destroy(oled_class);
  unregister_chrdev(major_num, DEVICE_NAME);

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 11, 0)
  return 0;
#endif
}

static const struct of_device_id zed_oled_of_match[] = {
    {
        .compatible = "digilent,zed-oled-emio",
    },
    {/* sentinel */}};
MODULE_DEVICE_TABLE(of, zed_oled_of_match);

static struct platform_driver zed_oled_driver = {
    .probe = zed_oled_probe,
    .remove = zed_oled_remove,
    .driver = {
        .name = DEVICE_NAME,
        .of_match_table = zed_oled_of_match,
    },
};

module_platform_driver(zed_oled_driver);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("ZedBoard SSD1306 OLED bit-banged EMIO driver");
