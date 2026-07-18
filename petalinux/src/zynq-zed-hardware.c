#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <syslog.h>
#include <time.h>
#include <unistd.h>

// =============================================================================
// Configuration
// =============================================================================
// Per-device mmap window sizes (MUST match /sys/class/uio/uioN/maps/map0/size)
#define MAP_SIZE_GPIO 0x1000  // AXI GPIO cores  = 4 KB
#define MAP_SIZE_BRAM 0x2000  // AXI BRAM ctrl   = 8 KB

// --- UIO device nodes (verified via /sys/class/uio/uioN/name) ---
#define UIO_BRAM_DEV "/dev/uio0"  // axi_bram_ctrl@40000000  (8 KB, no IRQ)
#define UIO_GPIO_DEV "/dev/uio1"  // gpio@41200000 switches/LEDs, SPI 62 / virq 39
#define UIO_BTN_DEV "/dev/uio2"   // gpio@41210000 buttons,       SPI 61 / virq 40

// --- AXI GPIO register offsets ---
#define GPIO_DATA_OFFSET 0x0000   // Ch1 Data (LEDs / buttons)
#define GPIO_TRI_OFFSET 0x0004    // Ch1 Direction
#define GPIO2_DATA_OFFSET 0x0008  // Ch2 Data (switches)
#define GPIO2_TRI_OFFSET 0x000C   // Ch2 Direction
#define GPIO_GIER 0x011C          // Global IRQ Enable (bit31)
#define GPIO_IPISR 0x0120         // IRQ Status (write-1-to-clear)
#define GPIO_IPIER 0x0128         // IRQ Enable (bit0=Ch1, bit1=Ch2)

// --- Button core (single channel, 5 buttons on Ch1) ---
#define BTN_DATA_OFFSET 0x0000
#define BTN_MASK 0x1F
#define BTN_CENTER 0x01
#define BTN_DOWN 0x02
#define BTN_LEFT 0x04
#define BTN_RIGHT 0x08
#define BTN_UP 0x10

// --- BRAM ---
#define BRAM_ADDR_OFFSET 0x0004
#define BRAM_DEPTH_WORDS 16

// --- LED bit ownership: bits 0-6 = switches, bit 7 = heartbeat ---
#define LED_SWITCH_MASK 0x7F
#define LED_HEARTBEAT_MASK 0x80

// --- Timing ---
#define DEBOUNCE_MS 15
#define HEARTBEAT_PERIOD_MS 500
#define CLIENT_RECV_TIMEOUT 5  // seconds; kill slow/idle HTTP clients

// --- Server / logging ---
#define HTTP_PORT 8080
#define LOG_FILE_PATH "/var/log/bram_telemetry_log.csv"
#define AUTH_TOKEN "ZynqSecure2026Token#"

// Signal used only to interrupt blocking read() in worker threads on shutdown.
#define SIG_WAKE SIGUSR1

// --- Register access macros ---
#define REG_WRITE(base, offset, data) (*(volatile uint32_t *) ((uintptr_t) (base) + (offset)) = (data))
#define REG_READ(base, offset) (*(volatile uint32_t *) ((uintptr_t) (base) + (offset)))

// =============================================================================
// Globals
// =============================================================================
uint8_t *gpio_ptr = NULL;
uint8_t *bram_ptr = NULL;
uint8_t *btn_ptr = NULL;

int uio_gpio_fd = -1;
int uio_bram_fd = -1;
int uio_btn_fd = -1;

uint32_t local_bram_cache[BRAM_DEPTH_WORDS] = {0};
volatile uint32_t current_switches = 0;
volatile uint32_t current_buttons = 0;

uint8_t led_state = 0;  // authoritative LED shadow (guarded by hardware_mutex)

volatile sig_atomic_t keep_running = 1;
FILE *csv_log = NULL;

pthread_mutex_t hardware_mutex = PTHREAD_MUTEX_INITIALIZER;

// =============================================================================
// Utilities
// =============================================================================

// Guaranteed full write (handles short writes / EINTR).
static ssize_t write_all(int fd, const void *buf, size_t len)
{
  const char *p = (const char *) buf;
  size_t left = len;
  while (left)
  {
    ssize_t n = write(fd, p, left);
    if (n < 0)
    {
      if (errno == EINTR) continue;
      return -1;
    }
    p += n;
    left -= (size_t) n;
  }
  return (ssize_t) len;
}

// Read an HTTP request until header terminator or buffer full.
static ssize_t read_http_request(int fd, char *buf, size_t cap)
{
  size_t total = 0;
  while (total < cap - 1)
  {
    ssize_t n = read(fd, buf + total, cap - 1 - total);
    if (n < 0)
    {
      if (errno == EINTR) continue;
      return -1;  // includes EAGAIN/EWOULDBLOCK from recv timeout
    }
    if (n == 0) break;
    total += (size_t) n;
    buf[total] = '\0';
    if (strstr(buf, "\r\n\r\n") != NULL) break;
  }
  buf[total] = '\0';
  return (ssize_t) total;
}

// Append a change record to CSV. Call under hardware_mutex.
static void log_change_csv(uint32_t offset, uint32_t value)
{
  if (csv_log == NULL) return;
  time_t now = time(NULL);
  struct tm *t = localtime(&now);
  char ts[32];
  strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", t);
  fprintf(csv_log, "%s,%u,%u\n", ts, offset, value);
  fflush(csv_log);
}

// Merge bits into LED shadow + push to hardware. Call under hardware_mutex.
static inline void led_apply(uint8_t clear_mask, uint8_t set_bits)
{
  led_state = (uint8_t) ((led_state & ~clear_mask) | (set_bits & clear_mask));
  REG_WRITE(gpio_ptr, GPIO_DATA_OFFSET, led_state);
}

void handle_term(int sig)
{
  (void) sig;
  keep_running = 0;
}

void handle_wake(int sig)
{
  (void) sig;  // no-op: exists only to make blocking read() return EINTR
}

// =============================================================================
// HTML Dashboard
// =============================================================================
const char *html_dashboard =
    "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n"
    "<!DOCTYPE html><html lang='en'><head><meta charset='UTF-8'><title>Zynq Telemetry Dashboard</title>"
    "<script src='https://cdn.tailwindcss.com'></script>"
    "</head><body class='bg-slate-900 text-slate-100 font-sans p-8'>"
    "<div class='max-w-4xl mx-auto'><header class='flex justify-between items-center mb-8 border-b border-slate-700 pb-4'>"
    "<div><h1 class='text-3xl font-extrabold text-sky-400 tracking-tight'>Zynq-7000 SoC Dashboard</h1>"
    "<p class='text-slate-400 text-sm'>Real-Time Hardware Monitor & Teleoperation Portal</p></div>"
    "<div class='flex items-center gap-2'><span class='w-3 h-3 bg-emerald-500 rounded-full animate-pulse'></span>"
    "<span class='text-sm text-slate-300 font-medium'>System Status: Active</span></div></header>"
    "<div class='grid grid-cols-1 md:grid-cols-3 gap-6 mb-8'>"
    "<div class='bg-slate-800 p-6 rounded-xl border border-slate-700 shadow-xl'>"
    "<h3 class='text-slate-400 text-sm font-semibold uppercase tracking-wider mb-2'>Switch Inputs</h3>"
    "<div id='switches' class='text-4xl font-mono font-bold text-amber-400'>0x00</div></div>"
    "<div class='bg-slate-800 p-6 rounded-xl border border-slate-700 shadow-xl'>"
    "<h3 class='text-slate-400 text-sm font-semibold uppercase tracking-wider mb-2'>Buttons</h3>"
    "<div id='buttons' class='text-4xl font-mono font-bold text-emerald-400'>0x00</div></div>"
    "<div class='bg-slate-800 p-6 rounded-xl border border-slate-700 shadow-xl'>"
    "<h3 class='text-slate-400 text-sm font-semibold uppercase tracking-wider mb-2'>Security Token</h3>"
    "<div id='token-status' class='text-lg font-semibold text-rose-400 truncate mt-2'>Loaded</div></div></div>"
    "<div class='bg-slate-800 rounded-xl border border-slate-700 shadow-xl p-6 mb-8'>"
    "<h2 class='text-xl font-bold mb-4 text-sky-400'>Memory Control Matrix</h2>"
    "<div class='flex gap-2 mb-6'><input id='token' type='password' placeholder='Security Token' class='bg-slate-900 border border-slate-700 rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-sky-500 w-1/4'>"
    "<select id='offset' class='bg-slate-900 border border-slate-700 rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-sky-500 w-1/4'></select>"
    "<input id='value' type='number' placeholder='Value (32-bit uint)' class='bg-slate-900 border border-slate-700 rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-sky-500 w-1/4'>"
    "<button onclick='writeRegister()' class='bg-sky-500 hover:bg-sky-600 transition text-white text-sm font-bold px-6 py-2 rounded-lg cursor-pointer shadow-lg shadow-sky-500/20'>Commit Write</button></div>"
    "<div class='overflow-x-auto'><table class='w-full text-left font-mono text-sm'><thead class='bg-slate-900 text-slate-400 uppercase text-xs tracking-wider border-b border-slate-700'><tr><th class='p-3'>Register Offset</th><th class='p-3'>Value</th></tr></thead>"
    "<tbody id='reg-table' class='divide-y divide-slate-700'></tbody></table></div></div></div>"
    "<script>"
    "const base = window.location.origin; const sel = document.getElementById('offset');"
    "for(let i=0;i<16;i++){const o=document.createElement('option');o.value=i*4;o.textContent=`Offset ${i*4} (0x${(i*4).toString(16).toUpperCase().padStart(2,'0')})`;sel.appendChild(o);}"
    "async function poll(){try{const r=await fetch(`${base}/api/read`);const d=await r.json();"
    "document.getElementById('switches').textContent=`0x${d.switches.toString(16).toUpperCase().padStart(2,'0')}`;"
    "document.getElementById('buttons').textContent=`0x${d.buttons.toString(16).toUpperCase().padStart(2,'0')}`;"
    "const tb=document.getElementById('reg-table');tb.innerHTML='';"
    "d.bram_registers.forEach(x=>{const tr=document.createElement('tr');tr.className='hover:bg-slate-700/50 transition';"
    "tr.innerHTML=`<td class='p-3 text-slate-300'>0x${x.offset.toString(16).toUpperCase().padStart(2,'0')} (${x.offset})</td><td class='p-3 font-bold text-sky-400'>${x.value}</td>`;"
    "tb.appendChild(tr);});}catch(e){console.error(e);}}"
    "async function writeRegister(){const t=document.getElementById('token').value;const o=document.getElementById('offset').value;const v=document.getElementById('value').value;"
    "try{const r=await fetch(`${base}/api/write?offset=${o}&value=${v}`,{method:'POST',headers:{'Authorization':`Bearer ${t}`}});"
    "const d=await r.json();if(d.status==='success')alert(`Success! Wrote ${v} to offset ${o}`);else alert(`Error: ${d.message}`);poll();}catch(e){alert('Communication failed.');}}"
    "setInterval(poll,1000);poll();"
    "</script></body></html>";

// =============================================================================
// Thread: Switch IRQ -> edge-driven, debounced LEDs
// =============================================================================
void *switch_irq_thread(void *arg)
{
  (void) arg;
  uint32_t reenable = 1, irq_count;

  while (keep_running)
  {
    if (write(uio_gpio_fd, &reenable, sizeof(reenable)) != (ssize_t) sizeof(reenable))
    {
      if (errno == EINTR) continue;
      break;
    }
    ssize_t n = read(uio_gpio_fd, &irq_count, sizeof(irq_count));
    if (n != (ssize_t) sizeof(irq_count))
    {
      if (errno == EINTR) continue;  // woken by SIG_WAKE on shutdown
      break;
    }
    if (!keep_running) break;

    // Debounce: require 3 consistent reads
    uint32_t sample = 0, prev = ~0u;
    for (int stable = 0; stable < 3 && keep_running;)
    {
      usleep(DEBOUNCE_MS * 1000);
      sample = REG_READ(gpio_ptr, GPIO2_DATA_OFFSET);
      stable = (sample == prev) ? (stable + 1) : 0;
      prev = sample;
    }

    pthread_mutex_lock(&hardware_mutex);
    uint32_t isr = REG_READ(gpio_ptr, GPIO_IPISR);
    REG_WRITE(gpio_ptr, GPIO_IPISR, isr);  // clear all pending
    current_switches = sample;
    led_apply(LED_SWITCH_MASK, (uint8_t) (sample & LED_SWITCH_MASK));
    pthread_mutex_unlock(&hardware_mutex);

    syslog(LOG_INFO, "SW IRQ: switches=0x%02X", sample & 0xFF);
  }
  return NULL;
}

// =============================================================================
// Thread: Button IRQ -> debounced actions
// =============================================================================
void *button_irq_thread(void *arg)
{
  (void) arg;
  uint32_t reenable = 1, irq_count, prev_state = 0;

  while (keep_running)
  {
    if (write(uio_btn_fd, &reenable, sizeof(reenable)) != (ssize_t) sizeof(reenable))
    {
      if (errno == EINTR) continue;
      break;
    }
    ssize_t n = read(uio_btn_fd, &irq_count, sizeof(irq_count));
    if (n != (ssize_t) sizeof(irq_count))
    {
      if (errno == EINTR) continue;  // woken by SIG_WAKE on shutdown
      break;
    }
    if (!keep_running) break;

    // Debounce
    uint32_t sample = 0, prev = ~0u;
    for (int stable = 0; stable < 3 && keep_running;)
    {
      usleep(DEBOUNCE_MS * 1000);
      sample = REG_READ(btn_ptr, BTN_DATA_OFFSET) & BTN_MASK;
      stable = (sample == prev) ? (stable + 1) : 0;
      prev = sample;
    }

    pthread_mutex_lock(&hardware_mutex);
    uint32_t isr = REG_READ(btn_ptr, GPIO_IPISR);
    REG_WRITE(btn_ptr, GPIO_IPISR, isr);
    current_buttons = sample;

    uint32_t pressed = sample & ~prev_state;  // rising edges
    prev_state = sample;

    if (pressed & BTN_CENTER)
      led_apply(LED_SWITCH_MASK, (uint8_t) (~led_state & LED_SWITCH_MASK));  // flash
    if (pressed & BTN_UP)
    {
      REG_WRITE(bram_ptr, 0x0, 0xDEAD0001);
      local_bram_cache[0] = 0xDEAD0001;
      log_change_csv(0x0, 0xDEAD0001);
    }
    if (pressed & BTN_DOWN)
    {
      REG_WRITE(bram_ptr, 0x0, 0x0);
      local_bram_cache[0] = 0x0;
      log_change_csv(0x0, 0x0);
    }
    // BTN_LEFT / BTN_RIGHT reserved (e.g., OLED page navigation)
    pthread_mutex_unlock(&hardware_mutex);

    if (pressed)
      syslog(LOG_INFO, "BTN: raw=0x%02X pressed=0x%02X", sample, pressed);
  }
  return NULL;
}

// =============================================================================
// Thread: Heartbeat LED (bit 7)
// =============================================================================
void *heartbeat_thread(void *arg)
{
  (void) arg;
  bool on = false;

  while (keep_running)
  {
    on = !on;
    pthread_mutex_lock(&hardware_mutex);
    led_apply(LED_HEARTBEAT_MASK, on ? LED_HEARTBEAT_MASK : 0x00);
    pthread_mutex_unlock(&hardware_mutex);

    for (int i = 0; i < HEARTBEAT_PERIOD_MS / 10 && keep_running; i++)
      usleep(10 * 1000);
  }
  return NULL;
}

// =============================================================================
// Thread: HTTP server
// =============================================================================
void *web_server_thread(void *arg)
{
  (void) arg;
  int server_fd, client_fd;
  struct sockaddr_in address;

  server_fd = socket(AF_INET, SOCK_STREAM, 0);
  if (server_fd < 0)
  {
    syslog(LOG_ERR, "socket failed");
    return NULL;
  }

  int opt = 1;
  setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

  address.sin_family = AF_INET;
  address.sin_addr.s_addr = INADDR_ANY;
  address.sin_port = htons(HTTP_PORT);

  if (bind(server_fd, (struct sockaddr *) &address, sizeof(address)) < 0)
  {
    syslog(LOG_ERR, "bind failed on port %d", HTTP_PORT);
    close(server_fd);
    return NULL;
  }
  listen(server_fd, 10);
  fcntl(server_fd, F_SETFL, O_NONBLOCK);

  while (keep_running)
  {
    socklen_t addrlen = sizeof(address);
    client_fd = accept(server_fd, (struct sockaddr *) &address, &addrlen);
    if (client_fd < 0)
    {
      usleep(10000);
      continue;
    }

    // Kill slow/idle clients so they can't hang this single-threaded server.
    struct timeval tv = {.tv_sec = CLIENT_RECV_TIMEOUT, .tv_usec = 0};
    setsockopt(client_fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

    char rx[2048] = {0}, json[1536] = {0}, hdr[512] = {0};

    if (read_http_request(client_fd, rx, sizeof(rx)) <= 0)
    {
      close(client_fd);
      continue;
    }

    // --- POST /api/write ---
    if (strstr(rx, "POST /api/write") != NULL)
    {
      char *auth = strstr(rx, "Authorization: Bearer ");
      bool ok = false;
      if (auth)
      {
        auth += 22;
        size_t tlen = strlen(AUTH_TOKEN);
        if (strncmp(auth, AUTH_TOKEN, tlen) == 0 &&
            (auth[tlen] == '\r' || auth[tlen] == '\n' || auth[tlen] == ' '))
          ok = true;
      }

      if (!ok)
      {
        snprintf(json, sizeof(json),
                 "{\"status\":\"error\",\"message\":\"Unauthorized!\"}");
        snprintf(hdr, sizeof(hdr),
                 "HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\n"
                 "Content-Length: %zu\r\nConnection: close\r\n\r\n",
                 strlen(json));
        write_all(client_fd, hdr, strlen(hdr));
        write_all(client_fd, json, strlen(json));
        close(client_fd);
        continue;
      }

      uint32_t off = 0, val = 0;
      char *q = strstr(rx, "offset=");
      if (q && sscanf(q, "offset=%u&value=%u", &off, &val) == 2)
      {
        if (off < (BRAM_DEPTH_WORDS * BRAM_ADDR_OFFSET) && (off % 4 == 0))
        {
          pthread_mutex_lock(&hardware_mutex);
          REG_WRITE(bram_ptr, off, val);
          local_bram_cache[off / BRAM_ADDR_OFFSET] = val;
          log_change_csv(off, val);
          pthread_mutex_unlock(&hardware_mutex);
          snprintf(json, sizeof(json),
                   "{\"status\":\"success\",\"offset\":%u,\"value\":%u}", off, val);
        }
        else
          snprintf(json, sizeof(json),
                   "{\"status\":\"error\",\"message\":\"Boundary offset error.\"}");
      }
      else
        snprintf(json, sizeof(json),
                 "{\"status\":\"error\",\"message\":\"Missing parameters.\"}");

      snprintf(hdr, sizeof(hdr),
               "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
               "Access-Control-Allow-Origin: *\r\nContent-Length: %zu\r\nConnection: close\r\n\r\n",
               strlen(json));
      write_all(client_fd, hdr, strlen(hdr));
      write_all(client_fd, json, strlen(json));
    }
    // --- GET /api/read ---
    else if (strstr(rx, "GET /api/read") != NULL)
    {
      pthread_mutex_lock(&hardware_mutex);
      uint32_t sw = current_switches, btn = current_buttons;
      int len = snprintf(json, sizeof(json),
                         "{\"switches\":%u,\"buttons\":%u,\"bram_registers\":[", sw, btn);
      for (int i = 0; i < BRAM_DEPTH_WORDS; i++)
      {
        if (len < 0 || (size_t) len >= sizeof(json)) break;
        len += snprintf(json + len, sizeof(json) - (size_t) len,
                        "{\"offset\":%d,\"value\":%u}%s",
                        i * BRAM_ADDR_OFFSET, local_bram_cache[i],
                        (i < BRAM_DEPTH_WORDS - 1) ? "," : "");
      }
      pthread_mutex_unlock(&hardware_mutex);
      if (len > 0 && (size_t) len < sizeof(json))
        snprintf(json + len, sizeof(json) - (size_t) len, "]}");

      snprintf(hdr, sizeof(hdr),
               "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
               "Access-Control-Allow-Origin: *\r\nContent-Length: %zu\r\nConnection: close\r\n\r\n",
               strlen(json));
      write_all(client_fd, hdr, strlen(hdr));
      write_all(client_fd, json, strlen(json));
    }
    // --- GET / (dashboard) ---
    else if (strstr(rx, "GET / ") != NULL || strstr(rx, "GET /index.html") != NULL)
      write_all(client_fd, html_dashboard, strlen(html_dashboard));
    // --- 404 ---
    else
    {
      const char *nf = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
      write_all(client_fd, nf, strlen(nf));
    }

    close(client_fd);
  }
  close(server_fd);
  return NULL;
}

// =============================================================================
// Helper: open + mmap a UIO device (size matched per-device)
// =============================================================================
static int uio_open_map(const char *dev, int *fd_out, uint8_t **map_out, size_t map_size)
{
  int fd = open(dev, O_RDWR);
  if (fd < 0)
  {
    syslog(LOG_ERR, "open %s: %m", dev);
    return -1;
  }
  uint8_t *m = mmap(NULL, map_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (m == MAP_FAILED)
  {
    syslog(LOG_ERR, "mmap %s (size 0x%zx): %m", dev, map_size);
    close(fd);
    return -1;
  }
  *fd_out = fd;
  *map_out = m;
  return 0;
}

// =============================================================================
// Main
// =============================================================================
int main(void)
{
  // --- Daemonize (double-fork) ---
  pid_t pid = fork();
  if (pid < 0) exit(EXIT_FAILURE);
  if (pid > 0) exit(EXIT_SUCCESS);

  umask(0);
  openlog("zynq_hardware_daemon", LOG_PID, LOG_DAEMON);

  if (setsid() < 0) exit(EXIT_FAILURE);

  pid = fork();  // second fork: ensure we can't reacquire a controlling TTY
  if (pid < 0) exit(EXIT_FAILURE);
  if (pid > 0) exit(EXIT_SUCCESS);

  if (chdir("/") < 0) exit(EXIT_FAILURE);

  close(STDIN_FILENO);
  close(STDOUT_FILENO);
  close(STDERR_FILENO);

  // --- Signals (no SA_RESTART so blocking calls return EINTR) ---
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = handle_term;
  sigaction(SIGINT, &sa, NULL);
  sigaction(SIGTERM, &sa, NULL);

  struct sigaction sw;  // wake signal for worker read() unblock
  memset(&sw, 0, sizeof(sw));
  sw.sa_handler = handle_wake;
  sigaction(SIG_WAKE, &sw, NULL);

  signal(SIGPIPE, SIG_IGN);  // don't die on client disconnect mid-write

  // --- Open UIO devices (per-device sizes!) ---
  if (uio_open_map(UIO_BRAM_DEV, &uio_bram_fd, &bram_ptr, MAP_SIZE_BRAM) < 0)
  {
    closelog();
    exit(EXIT_FAILURE);
  }
  if (uio_open_map(UIO_GPIO_DEV, &uio_gpio_fd, &gpio_ptr, MAP_SIZE_GPIO) < 0)
  {
    munmap(bram_ptr, MAP_SIZE_BRAM);
    close(uio_bram_fd);
    closelog();
    exit(EXIT_FAILURE);
  }
  if (uio_open_map(UIO_BTN_DEV, &uio_btn_fd, &btn_ptr, MAP_SIZE_GPIO) < 0)
  {
    munmap(bram_ptr, MAP_SIZE_BRAM);
    munmap(gpio_ptr, MAP_SIZE_GPIO);
    close(uio_bram_fd);
    close(uio_gpio_fd);
    closelog();
    exit(EXIT_FAILURE);
  }

  // --- GPIO directions ---
  REG_WRITE(gpio_ptr, GPIO_TRI_OFFSET, 0x00000000);   // Ch1 = LED outputs
  REG_WRITE(gpio_ptr, GPIO2_TRI_OFFSET, 0xFFFFFFFF);  // Ch2 = switch inputs

  // --- Switch IRQ enable (Channel 2) ---
  REG_WRITE(gpio_ptr, GPIO_IPISR, 0x3);
  REG_WRITE(gpio_ptr, GPIO_IPIER, 0x2);
  REG_WRITE(gpio_ptr, GPIO_GIER, 0x80000000);

  // --- Button IRQ enable (Channel 1) ---
  REG_WRITE(btn_ptr, GPIO_IPISR, 0x1);
  REG_WRITE(btn_ptr, GPIO_IPIER, 0x1);
  REG_WRITE(btn_ptr, GPIO_GIER, 0x80000000);

  // --- Prime caches + initial LED state ---
  for (int i = 0; i < BRAM_DEPTH_WORDS; i++)
    local_bram_cache[i] = REG_READ(bram_ptr, i * BRAM_ADDR_OFFSET);

  current_switches = REG_READ(gpio_ptr, GPIO2_DATA_OFFSET);
  current_buttons = REG_READ(btn_ptr, BTN_DATA_OFFSET) & BTN_MASK;

  pthread_mutex_lock(&hardware_mutex);
  led_apply(LED_SWITCH_MASK, (uint8_t) (current_switches & LED_SWITCH_MASK));
  pthread_mutex_unlock(&hardware_mutex);

  // --- CSV log ---
  csv_log = fopen(LOG_FILE_PATH, "a");
  if (csv_log)
  {
    fseek(csv_log, 0, SEEK_END);
    if (ftell(csv_log) == 0)
    {
      fprintf(csv_log, "Timestamp,Offset,Value\n");
      fflush(csv_log);
    }
  }

  // --- Launch threads (track which succeeded) ---
  pthread_t web_tid, sw_tid, btn_tid, hb_tid;
  bool web_ok = (pthread_create(&web_tid, NULL, web_server_thread, NULL) == 0);
  bool sw_ok = (pthread_create(&sw_tid, NULL, switch_irq_thread, NULL) == 0);
  bool btn_ok = (pthread_create(&btn_tid, NULL, button_irq_thread, NULL) == 0);
  bool hb_ok = (pthread_create(&hb_tid, NULL, heartbeat_thread, NULL) == 0);

  if (!web_ok) syslog(LOG_ERR, "web thread failed");
  if (!sw_ok) syslog(LOG_ERR, "switch thread failed");
  if (!btn_ok) syslog(LOG_ERR, "button thread failed");
  if (!hb_ok) syslog(LOG_ERR, "heartbeat thread failed");

  // --- Main loop: BRAM change monitor + CSV logging ---
  while (keep_running)
  {
    pthread_mutex_lock(&hardware_mutex);
    for (uint32_t a = 0; a < BRAM_DEPTH_WORDS; ++a)
    {
      uint32_t off = a * BRAM_ADDR_OFFSET;
      uint32_t v = REG_READ(bram_ptr, off);
      if (v != local_bram_cache[a])
      {
        local_bram_cache[a] = v;
        syslog(LOG_INFO, "BRAM change -> Offset: %u, Data: %u", off, v);
        log_change_csv(off, v);
      }
    }
    pthread_mutex_unlock(&hardware_mutex);

    // Sleep in slices for responsive shutdown.
    for (int i = 0; i < 100 && keep_running; i++)
      usleep(10 * 1000);
  }

  // --- Cleanup ---
  // Disable interrupts first so no new IRQ fires.
  REG_WRITE(gpio_ptr, GPIO_GIER, 0x0);
  REG_WRITE(gpio_ptr, GPIO_IPIER, 0x0);
  REG_WRITE(btn_ptr, GPIO_GIER, 0x0);
  REG_WRITE(btn_ptr, GPIO_IPIER, 0x0);

  // Wake IRQ threads blocked in read() so join() doesn't hang until next IRQ.
  if (sw_ok) pthread_kill(sw_tid, SIG_WAKE);
  if (btn_ok) pthread_kill(btn_tid, SIG_WAKE);

  if (sw_ok) pthread_join(sw_tid, NULL);
  if (btn_ok) pthread_join(btn_tid, NULL);
  if (hb_ok) pthread_join(hb_tid, NULL);
  if (web_ok) pthread_join(web_tid, NULL);

  pthread_mutex_destroy(&hardware_mutex);
  if (csv_log) fclose(csv_log);

  REG_WRITE(gpio_ptr, GPIO_DATA_OFFSET, 0x00000000);  // LEDs off

  munmap(gpio_ptr, MAP_SIZE_GPIO);
  munmap(bram_ptr, MAP_SIZE_BRAM);
  munmap(btn_ptr, MAP_SIZE_GPIO);
  close(uio_gpio_fd);
  close(uio_bram_fd);
  close(uio_btn_fd);
  closelog();

  return EXIT_SUCCESS;
}
