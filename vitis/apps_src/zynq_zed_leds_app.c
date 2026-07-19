#include <xgpio_l.h>
#include "platform.h"
#include "xgpio.h"
#include "xil_exception.h"
#include "xintc.h"  // For cascaded AXI Interrupt Controller
#include "xparameters.h"
#include "xscugic.h"  // For primary ARM processor interrupts

#define LED_CHANNEL 1
#define SWITCH_CHANNEL 2
#define LEDS_MASK 0xFF      // 8 leds
#define SWITCHES_MASK 0xFF  // 8 switches

#define DBUT_CHANNEL 1
#define DBUT_MASK 0x1F

// Device ID definition mapping for the driver initialization lookup
#define INTC_DEVICE_ID 0

// Sequential hardware input indexes extracted straight from your xparameters.h
#define AXI_INTC_GPIO0_INTR_ID XPAR_FABRIC_AXI_GPIO_0_INTR  // Maps to index 1
#define AXI_INTC_GPIO1_INTR_ID XPAR_FABRIC_AXI_GPIO_1_INTR  // Maps to index 0

// Hardcoded cascading mapping slot for Zynq IRQ_F2P on your Zedboard
#define ZYNQ_F2P_HARDWARE_ID 61U

XGpio Gpio0, Gpio1;
XScuGic IntcInstanceGic;  // Primary GIC Instance
XIntc IntcInstanceAxi;    // Cascaded AXI Intc Instance

// VISUAL ANCHOR: Global volatile flags for ISR communication
volatile u32 SwitchChangedFlag = 0;
volatile u32 ButtonChangedFlag = 0;

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
  // Set flag and exit immediately. Do not print here.
  SwitchChangedFlag = 1;
}

// Interrupt Handler for GPIO 1
void Gpio1_InterruptHandler(void *InstancePtr)
{
  XGpio_InterruptClear((XGpio *) InstancePtr, XGPIO_IR_CH1_MASK);
  // TODO: Add your custom GPIO 1 logic here
  // Set flag and exit immediately. Do not print here.
  ButtonChangedFlag = 1;
}

int SetupInterruptSystem()
{
  int Status;
  XScuGic_Config *GicConfig;

  // =========================================================================
  // STEP 1: Initialize Primary Zynq GIC
  // =========================================================================
  GicConfig = XScuGic_LookupConfig(XPAR_SCUGIC_SINGLE_DEVICE_ID);
  if (GicConfig == NULL)
  {
    return XST_FAILURE;
  }
  Status = XScuGic_CfgInitialize(&IntcInstanceGic, GicConfig, GicConfig->CpuBaseAddress);
  if (Status != XST_SUCCESS)
  {
    return Status;
  }

  // =========================================================================
  // STEP 2: Initialize Cascaded AXI Interrupt Controller (Fixed Clang Error)
  // =========================================================================
  Status = XIntc_Initialize(&IntcInstanceAxi, INTC_DEVICE_ID);
  if (Status != XST_SUCCESS)
  {
    return Status;
  }

  // =========================================================================
  // STEP 3: Connect AXI Intc Handler as a Sub-Routine to the Zynq GIC
  // =========================================================================
  u32 ZynqF2pIntrId = ZYNQ_F2P_HARDWARE_ID;

  XScuGic_SetPriorityTriggerType(&IntcInstanceGic, ZynqF2pIntrId, 0xA0, 3);

  Status = XScuGic_Connect(&IntcInstanceGic, ZynqF2pIntrId,
                           (Xil_ExceptionHandler) XIntc_InterruptHandler,
                           &IntcInstanceAxi);
  if (Status != XST_SUCCESS)
  {
    return Status;
  }
  XScuGic_Enable(&IntcInstanceGic, ZynqF2pIntrId);

  // =========================================================================
  // STEP 4: Connect GPIO Hardware Instances via your xparameters.h flags
  // =========================================================================
  Status = XIntc_Connect(&IntcInstanceAxi, AXI_INTC_GPIO0_INTR_ID,
                         (XInterruptHandler) Gpio0_InterruptHandler,
                         &Gpio0);
  if (Status != XST_SUCCESS)
  {
    return Status;
  }
  XIntc_Enable(&IntcInstanceAxi, AXI_INTC_GPIO0_INTR_ID);

  Status = XIntc_Connect(&IntcInstanceAxi, AXI_INTC_GPIO1_INTR_ID,
                         (XInterruptHandler) Gpio1_InterruptHandler,
                         &Gpio1);
  if (Status != XST_SUCCESS)
  {
    return Status;
  }
  XIntc_Enable(&IntcInstanceAxi, AXI_INTC_GPIO1_INTR_ID);

  // =========================================================================
  // STEP 5: Start Controllers and Enable Hardware Exception Lines
  // =========================================================================
  Status = XIntc_Start(&IntcInstanceAxi, XIN_REAL_MODE);
  if (Status != XST_SUCCESS)
  {
    return Status;
  }

  Xil_ExceptionInit();
  Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                               (Xil_ExceptionHandler) XScuGic_InterruptHandler,
                               &IntcInstanceGic);
  Xil_ExceptionEnable();

  // =========================================================================
  // STEP 6: Enable Individual Hardware Channels inside AXI Peripherals
  // =========================================================================
  XGpio_InterruptEnable(&Gpio0, XGPIO_IR_CH2_MASK);
  XGpio_InterruptGlobalEnable(&Gpio0);

  XGpio_InterruptEnable(&Gpio1, XGPIO_IR_CH1_MASK);
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
    if (SwitchChangedFlag)
    {
      SwitchChangedFlag = 0;  // Clear the application flag
      leds();                 // Process the slow operation safely out of ISR context
    }

    if (ButtonChangedFlag)
    {
      ButtonChangedFlag = 0;
      u32 buttons = XGpio_DiscreteRead(&Gpio1, DBUT_CHANNEL);
      xil_printf("Button Pressed: 0x%02x\r\n", buttons);
    }
  }

  cleanup_platform();
  return 0;
}
