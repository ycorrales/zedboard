#include "platform.h"
#include "sleep.h"
#include "xbram.h"
#include "xgpio.h"
#include "xil_printf.h"
#include "xparameters.h"

#define LED_CHANNEL 1
#define SWITCH_CHANNEL 2
#define LEDS_MASK 0xFF      // 8 leds
#define SWITCHES_MASK 0xFF  // 8 switches

int main()
{
  init_platform();

  XBram Bram; /* The Instance of the BRAM Driver */
  XBram_Config *ConfigPtr;

  int Status;

  ConfigPtr = XBram_LookupConfig(XPAR_XBRAM_0_BASEADDR);
  if (ConfigPtr == (XBram_Config *) NULL)
  {
    return XST_FAILURE;
  }

  Status = XBram_CfgInitialize(&Bram, ConfigPtr,
                               ConfigPtr->CtrlBaseAddress);
  if (Status != XST_SUCCESS)
  {
    return XST_FAILURE;
  }

  xil_printf("Zynq on zedboard example\n\r");
  xil_printf("Successfully ran Fibbonacci application\n\r");

  xil_printf("Check write/read BRAM address\n\r");
  for (int addr = 0; addr < 16 * 4; addr += 4)
  {
    XBram_WriteReg(XPAR_XBRAM_0_BASEADDR, addr, addr);
  }

  unsigned int out_data;

  for (int addr = 0; addr < 16 * 4; addr += 4)
  {
    out_data = XBram_ReadReg(XPAR_XBRAM_0_BASEADDR, addr);
    xil_printf("%d: %d\n\r", addr, out_data);
    Xil_Out32(XPAR_XBRAM_0_BASEADDR + addr, 0x00000000);
  }

  xil_printf("Running Fibbonacci:\n\r");
  while (1)
  {
    int cnt_lines = 0;
    for (int addr = 0; addr < 20 * 4; addr += 4)
    {
      out_data = XBram_ReadReg(XPAR_XBRAM_0_BASEADDR, addr);

      // FIXED: Added \33[K so old BRAM values get wiped if digits shrink (e.g. 1000 down to 0)
      xil_printf("\33[K%u: %u\n\r", addr, out_data);
      ++cnt_lines;
    }

    // Moves the cursor up dynamically by 'cnt_lines', then resets to start of line
    xil_printf("\33[%dA\r", cnt_lines);
    sleep(1);
  }

  cleanup_platform();
  return 0;
}
