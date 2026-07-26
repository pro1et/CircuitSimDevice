#include "fir_fit.h"
#include "shared_bram_protocol.h"
#include "sweep_iq.h"

#include "sleep.h"
#include "xil_printf.h"
#include "xstatus.h"

#include <limits.h>
#include <math.h>
#include <stdint.h>

#define FIR_TAP_COUNT       129U
#define FIR_RIDGE_FACTOR    1e-6
#define BRAM_POLL_PERIOD_US 1000UL

static fir_fit_workspace_t fir_workspace;
static float floating_coefficients[FIR_TAP_COUNT];
static int32_t q31_coefficients[FIR_TAP_COUNT];

static int iq_to_complex_response(const sweep_iq_point_t *iq,
                                  double *response_real,
                                  double *response_imag)
{
    double direct_i = (double)iq->i_direct;
    double direct_q = (double)iq->q_direct;
    double filtered_i = (double)iq->i_filtered;
    double filtered_q = (double)iq->q_filtered;
    double denominator = direct_i * direct_i + direct_q * direct_q;

    if (denominator == 0.0) {
        return XST_FAILURE;
    }

    *response_real = (filtered_i * direct_i + filtered_q * direct_q)
                   / denominator;
    *response_imag = (filtered_q * direct_i - filtered_i * direct_q)
                   / denominator;
    return XST_SUCCESS;
}

static int float_to_q31(float coefficient, int32_t *quantized,
                        u32 *saturation_count)
{
    double scaled;

    if ((quantized == NULL) || !isfinite(coefficient)) {
        return XST_FAILURE;
    }

    scaled = (double)coefficient * 2147483648.0;
    if (scaled >= (double)INT32_MAX) {
        *quantized = INT32_MAX;
        ++(*saturation_count);
    } else if (scaled <= (double)INT32_MIN) {
        *quantized = INT32_MIN;
        ++(*saturation_count);
    } else if (scaled >= 0.0) {
        *quantized = (int32_t)(scaled + 0.5);
    } else {
        *quantized = (int32_t)(scaled - 0.5);
    }
    return XST_SUCCESS;
}

static u32 generate_q31_fir(u32 *valid_point_count,
                            u32 *saturation_count)
{
    const sweep_iq_config_t *sweep = sweep_iq_get_config();
    fir_fit_config_t fit_config = {
        (double)sweep->adc_sample_rate_hz,
        FIR_TAP_COUNT,
        FIR_RIDGE_FACTOR
    };
    u32 index;
    int fit_status;

    *valid_point_count = 0U;
    *saturation_count = 0U;

    fit_status = fir_fit_initialize(&fir_workspace, &fit_config);
    if (fit_status != FIR_FIT_SUCCESS) {
        return SHARED_BRAM_COEFF_ERROR_FIR_INITIALIZE;
    }

    for (index = 0U; index < sweep->point_count; ++index) {
        sweep_iq_point_t iq;
        double response_real;
        double response_imag;

        if (sweep_iq_read_point(index, &iq) != XST_SUCCESS) {
            return SHARED_BRAM_COEFF_ERROR_IQ_READ;
        }

        /* A zero direct IQ sample cannot define Y/X; skip that point. */
        if (iq_to_complex_response(&iq, &response_real,
                                   &response_imag) != XST_SUCCESS) {
            continue;
        }

        fit_status = fir_fit_add_sample(
            &fir_workspace,
            (double)iq.frequency_hz,
            response_real,
            response_imag);
        if (fit_status != FIR_FIT_SUCCESS) {
            return SHARED_BRAM_COEFF_ERROR_FIR_SOLVE;
        }
        ++(*valid_point_count);
    }

    if (*valid_point_count < FIR_TAP_COUNT) {
        return SHARED_BRAM_COEFF_ERROR_TOO_FEW_POINTS;
    }

    fit_status = fir_fit_solve(
        &fir_workspace,
        floating_coefficients,
        FIR_TAP_COUNT);
    if (fit_status != FIR_FIT_SUCCESS) {
        return SHARED_BRAM_COEFF_ERROR_FIR_SOLVE;
    }

    for (index = 0U; index < FIR_TAP_COUNT; ++index) {
        if (float_to_q31(floating_coefficients[index],
                         &q31_coefficients[index],
                         saturation_count) != XST_SUCCESS) {
            return SHARED_BRAM_COEFF_ERROR_QUANTIZE;
        }
    }

    return 0U;
}

int main(void)
{
    u32 last_processed_measurement_generation = 0U;
    int have_processed_generation = 0;
    int last_poll_error = SHARED_BRAM_OK;

    /* Zero/BUSY is published before PS has any valid coefficient set. */
    shared_bram_set_busy((UINTPTR)SHARED_BRAM_COEFF_BASE_ADDRESS);

    xil_printf("\r\nPS BRAM FIR pipeline started\r\n");
    xil_printf("measurement=0x%08x, coefficient=0x%08x, taps=%u\r\n",
               SHARED_BRAM_MEAS_BASE_ADDRESS,
               SHARED_BRAM_COEFF_BASE_ADDRESS,
               FIR_TAP_COUNT);

    for (;;) {
        shared_bram_result_t poll_result = sweep_iq_poll_snapshot();
        const shared_bram_measurement_info_t *measurement_info;
        u32 valid_point_count;
        u32 saturation_count;
        u32 coefficient_error;
        u32 coefficient_generation;

        if ((poll_result == SHARED_BRAM_NOT_READY)
            || (poll_result == SHARED_BRAM_RETRY)) {
            usleep(BRAM_POLL_PERIOD_US);
            continue;
        }

        if (poll_result != SHARED_BRAM_OK) {
            if ((int)poll_result != last_poll_error) {
                xil_printf("MEASUREMENT_PROTOCOL_ERROR,status=%d\r\n",
                           (int)poll_result);
                last_poll_error = (int)poll_result;
            }
            usleep(BRAM_POLL_PERIOD_US);
            continue;
        }
        last_poll_error = SHARED_BRAM_OK;
        measurement_info = sweep_iq_get_measurement_info();

        if (have_processed_generation
            && (measurement_info->generation
                == last_processed_measurement_generation)) {
            usleep(BRAM_POLL_PERIOD_US);
            continue;
        }

        xil_printf("MEASUREMENT_READY,generation=%u,words=%u,points=%u\r\n",
                   measurement_info->generation,
                   measurement_info->word_count,
                   sweep_iq_get_config()->point_count);

        coefficient_error = generate_q31_fir(
            &valid_point_count,
            &saturation_count);

        if (coefficient_error != 0U) {
            shared_bram_publish_coefficient_error(
                (UINTPTR)SHARED_BRAM_COEFF_BASE_ADDRESS,
                coefficient_error,
                &coefficient_generation);
            xil_printf("COEFFICIENT_ERROR,measurement_generation=%u,error=%u,coefficient_generation=%u\r\n",
                       measurement_info->generation,
                       coefficient_error,
                       coefficient_generation);
        } else {
            shared_bram_result_t publish_result =
                shared_bram_publish_coefficients_q31(
                    (UINTPTR)SHARED_BRAM_COEFF_BASE_ADDRESS,
                    SHARED_BRAM_COEFF_SIZE_BYTES,
                    q31_coefficients,
                    FIR_TAP_COUNT,
                    &coefficient_generation);

            if (publish_result == SHARED_BRAM_OK) {
                xil_printf("COEFFICIENT_VALID,measurement_generation=%u,coefficient_generation=%u,taps=%u,fit_points=%u,saturated=%u\r\n",
                           measurement_info->generation,
                           coefficient_generation,
                           FIR_TAP_COUNT,
                           valid_point_count,
                           saturation_count);
            } else {
                xil_printf("COEFFICIENT_PUBLISH_ERROR,status=%d\r\n",
                           (int)publish_result);
            }
        }

        last_processed_measurement_generation =
            measurement_info->generation;
        have_processed_generation = 1;
    }

    return XST_SUCCESS;
}
