#include <xgpio_l.h>
#include "platform.h"
#include "xgpio.h"
#include "xil_exception.h"
#include "xparameters.h"
#include "xscugic.h"

#define LED_CHANNEL 1
#define SWITCH_CHANNEL 2
#define LEDS_MASK 0xFF      // 8 leds
#define SWITCHES_MASK 0xFF  // 8 switches

#define DBUT_CHANNEL 1
#define DBUT_MASK 0x1F

XGpio Gpio0, Gpio1;
XScuGic Intc;

void leds()
{
  u32 switches = XGpio_DiscreteRead(&Gpio0, SWITCH_CHANNEL);
  XGpio_DiscreteWrite(&Gpio0, LED_CHANNEL, switches);

  // FIXED: Clear line before printing the switch status
  xil_printf("\33[KChecked! 0x%02x\n\r", switches);
  xil_printf("\33[%dA\r", 1);
};

// Interrupt Handler for GPIO 0
void Gpio0_InterruptHandler(void *InstancePtr)
{
  XGpio_InterruptClear((XGpio *) InstancePtr, XGPIO_IR_CH2_MASK);
  // TODO: Add your custom GPIO 0 logic here (e.g., toggle an LED, set a flag)
  leds();
}

// Interrupt Handler for GPIO 1
void Gpio1_InterruptHandler(void *InstancePtr)
{
  XGpio_InterruptClear((XGpio *) InstancePtr, XGPIO_IR_CH1_MASK);
  // TODO: Add your custom GPIO 1 logic here
}

int SetupInterruptSystem()
{
  XScuGic_Config *IntcConfig;
  int Status;

  // 1. Initialize the Interrupt Controller
  IntcConfig = XScuGic_LookupConfig(XPAR_SCUGIC_SINGLE_DEVICE_ID);
  if (IntcConfig == NULL)
  {
    return XST_FAILURE;
  }
  Status = XScuGic_CfgInitialize(&Intc, IntcConfig, IntcConfig->CpuBaseAddress);
  if (Status != XST_SUCCESS)
  {
    return Status;
  }

  // Calculate the REAL GIC IDs required by adding the 32 SPI architecture offset
  // Vitis Unified extracted the index 30, but forgot to add the architecture offset.
  u32 RealGpio0IntrId = XPAR_FABRIC_AXI_GPIO_0_INTR + 32;  // Resolves to 62
  u32 RealGpio1IntrId = XPAR_FABRIC_AXI_GPIO_1_INTR + 32;  // Resolves to 61

  // 2. Set the priority and trigger type to Level-Sensitive Active-High (Required for AXI GPIO)
  XScuGic_SetPriorityTriggerType(&Intc, RealGpio0IntrId, 0xA0, 3);
  XScuGic_SetPriorityTriggerType(&Intc, RealGpio1IntrId, 0xA0, 3);

  // 3. Connect and Enable GPIO 0 Handler (Switches & LEDs)
  Status = XScuGic_Connect(&Intc, RealGpio0IntrId, (Xil_ExceptionHandler) Gpio0_InterruptHandler, &Gpio0);
  if (Status != XST_SUCCESS)
  {
    return Status;
  }
  XScuGic_Enable(&Intc, RealGpio0IntrId);

  // 4. Connect and Enable GPIO 1 Handler (Buttons)
  Status = XScuGic_Connect(&Intc, RealGpio1IntrId, (Xil_ExceptionHandler) Gpio1_InterruptHandler, &Gpio1);
  if (Status != XST_SUCCESS)
  {
    return Status;
  }
  XScuGic_Enable(&Intc, RealGpio1IntrId);

  // 5. Enable hardware CPU exception handling hooks
  Xil_ExceptionInit();
  Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT, (Xil_ExceptionHandler) XScuGic_InterruptHandler, &Intc);
  Xil_ExceptionEnable();

  // 6. Enable individual AXI peripheral channel interrupt logic
  XGpio_InterruptEnable(&Gpio0, XGPIO_IR_CH2_MASK);  // Enable Channel 2 explicitly for Switches
  XGpio_InterruptGlobalEnable(&Gpio0);

  XGpio_InterruptEnable(&Gpio1, XGPIO_IR_CH1_MASK);  // Enable Channel 1 explicitly for Buttons
  XGpio_InterruptGlobalEnable(&Gpio1);

  return XST_SUCCESS;
}

// FIXED: Added the required entry point function
int main(void)
{
  init_platform();

  int Status;

  // Initialize GPIO 0 Hardware Driver Instance
  Status = XGpio_Initialize(&Gpio0, XPAR_XGPIO_0_BASEADDR);
  if (Status != XST_SUCCESS)
  {
    return XST_FAILURE;
  }

  /* Set the direction for all signals  */
  XGpio_SetDataDirection(&Gpio0, LED_CHANNEL, ~LEDS_MASK);        // 0 -> output
  XGpio_SetDataDirection(&Gpio0, SWITCH_CHANNEL, SWITCHES_MASK);  // 1- input

  // Initialize GPIO 1 Hardware Driver Instance
  Status = XGpio_Initialize(&Gpio1, XPAR_XGPIO_1_BASEADDR);
  if (Status != XST_SUCCESS)
  {
    return XST_FAILURE;
  }

  // Set Channel 1 of GPIO 1 to all inputs
  XGpio_SetDataDirection(&Gpio1, DBUT_CHANNEL, DBUT_MASK);

  print("Zynq on zedboard example\n\r");
  print("Successfully ran leds application\n\r");

  // Configure and hook up the GIC vector table
  Status = SetupInterruptSystem();
  if (Status != XST_SUCCESS)
  {
    return XST_FAILURE;
  }

  leds();

  // Infinite processing loop waiting for interrupts
  while (1)
  {
    // The CPU will stay here; when an input toggles, the GIC will jump to handlers
  }

  cleanup_platform();
  return 0;
}
