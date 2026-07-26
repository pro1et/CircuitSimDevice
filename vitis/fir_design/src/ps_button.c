#include "ps_button.h"

#include "sleep.h"
#include "xil_io.h"
#include "xil_types.h"

/* Mizar Z7 K3 / PS_KEY2 is connected to Zynq PS MIO47, active low. */
#define PS_GPIO_BASE_ADDRESS       0xE000A000U
#define PS_GPIO_BANK1_DATA_RO      (PS_GPIO_BASE_ADDRESS + 0x64U)
#define PS_GPIO_BANK1_DIRECTION    (PS_GPIO_BASE_ADDRESS + 0x244U)
#define PS_KEY2_BANK1_BIT          (1U << (47U - 32U))

#define BUTTON_POLL_INTERVAL_US    1000UL
#define BUTTON_DEBOUNCE_US         20000UL

static int ps_button_is_pressed(void)
{
    return (Xil_In32(PS_GPIO_BANK1_DATA_RO) & PS_KEY2_BANK1_BIT) == 0U;
}

void ps_button_init(void)
{
    u32 direction = Xil_In32(PS_GPIO_BANK1_DIRECTION);

    /* A cleared direction bit makes MIO47 an input. */
    direction &= ~PS_KEY2_BANK1_BIT;
    Xil_Out32(PS_GPIO_BANK1_DIRECTION, direction);
}

void ps_button_wait_for_press(void)
{
    /* Do not treat a button held during reset/download as a new press. */
    while (ps_button_is_pressed()) {
        usleep(BUTTON_POLL_INTERVAL_US);
    }

    for (;;) {
        while (!ps_button_is_pressed()) {
            usleep(BUTTON_POLL_INTERVAL_US);
        }

        usleep(BUTTON_DEBOUNCE_US);
        if (ps_button_is_pressed()) {
            return;
        }
    }
}
