#ifndef PS_BUTTON_H
#define PS_BUTTON_H

/*
 * Wait for one debounced press of the Mizar Z7 K3 / PS_KEY2 button.
 * The function first waits for a previously held button to be released.
 */
void ps_button_init(void);
void ps_button_wait_for_press(void);

#endif
