#include "transfer_function.h"

#include "xstatus.h"

#include <limits.h>
#include <stddef.h>

static u32 integer_sqrt_u64(u64 value)
{
    u64 result = 0U;
    u64 bit = (u64)1U << 62;

    while (bit > value) {
        bit >>= 2;
    }

    while (bit != 0U) {
        if (value >= result + bit) {
            value -= result + bit;
            result = (result >> 1) + bit;
        } else {
            result >>= 1;
        }
        bit >>= 2;
    }

    return (u32)result;
}

static s32 divide_q16(s64 numerator, u64 denominator)
{
    s64 quotient = (numerator * (s64)TRANSFER_FUNCTION_Q_ONE)
                 / (s64)denominator;

    if (quotient > (s64)INT_MAX) {
        return (s32)INT_MAX;
    }
    if (quotient < (s64)INT_MIN) {
        return (s32)INT_MIN;
    }
    return (s32)quotient;
}

int transfer_function_calculate(const sweep_iq_point_t *iq,
                                transfer_function_point_t *transfer)
{
    s64 direct_i;
    s64 direct_q;
    s64 filtered_i;
    s64 filtered_q;
    u64 direct_power;
    u64 filtered_power;
    s64 real_numerator;
    s64 imag_numerator;
    u64 magnitude_ratio_q32;

    if ((iq == NULL) || (transfer == NULL)) {
        return XST_INVALID_PARAM;
    }

    direct_i = (s64)iq->i_direct;
    direct_q = (s64)iq->q_direct;
    filtered_i = (s64)iq->i_filtered;
    filtered_q = (s64)iq->q_filtered;
    direct_power = (u64)(direct_i * direct_i + direct_q * direct_q);
    if (direct_power == 0U) {
        return XST_FAILURE;
    }

    filtered_power = (u64)(filtered_i * filtered_i
                           + filtered_q * filtered_q);
    real_numerator = filtered_i * direct_i + filtered_q * direct_q;
    imag_numerator = filtered_q * direct_i - filtered_i * direct_q;

    transfer->index = iq->index;
    transfer->frequency_hz = iq->frequency_hz;
    transfer->real_q16 = divide_q16(real_numerator, direct_power);
    transfer->imag_q16 = divide_q16(imag_numerator, direct_power);

    /* sqrt((|Y|^2 / |X|^2) * 2^32) gives |H| in unsigned Q16.16. */
    magnitude_ratio_q32 = (filtered_power << 32) / direct_power;
    transfer->magnitude_q16 = integer_sqrt_u64(magnitude_ratio_q32);

    return XST_SUCCESS;
}
