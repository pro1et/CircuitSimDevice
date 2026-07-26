#ifndef TRANSFER_FUNCTION_H
#define TRANSFER_FUNCTION_H

#include "sweep_iq.h"
#include "xil_types.h"

#define TRANSFER_FUNCTION_Q_FRACTION_BITS  16U
#define TRANSFER_FUNCTION_Q_ONE            65536U

typedef struct {
    u32 index;
    u32 frequency_hz;
    s32 real_q16;
    s32 imag_q16;
    u32 magnitude_q16;
} transfer_function_point_t;

int transfer_function_calculate(const sweep_iq_point_t *iq,
                                transfer_function_point_t *transfer);

#endif
