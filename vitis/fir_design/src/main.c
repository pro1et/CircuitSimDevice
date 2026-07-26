#include "sweep_iq.h"
#include "ps_button.h"
#include "transfer_function.h"
#include "fir_fit.h"

#include "xil_printf.h"
#include "xstatus.h"

#include <math.h>

typedef struct {
    u32 index;
    u32 frequency_hz;
    s16 i_direct;
    s16 q_direct;
    s16 i_filtered;
    s16 q_filtered;
} sweep_iq_expected_t;

static const sweep_iq_expected_t expected_points[] = {
    {0U,    200U,   4947, -11162, 1894, -11729},
    {1495U, 30100U, 4266, -10999,   -5,      4},
    {2990U, 60000U, 4267, -10995,   -6,      0}
};

#define TRANSFER_PRINT_TARGET_POINTS  300U
#define FIR_FIT_TAP_COUNT          129U
#define FIR_FIT_RIDGE_FACTOR       1e-6

static fir_fit_workspace_t fir_fit_workspace;
static float fitted_fir_coefficients[FIR_FIT_TAP_COUNT];

static int point_matches(const sweep_iq_point_t *point,
                         const sweep_iq_expected_t *expected)
{
    return (point->index == expected->index)
        && (point->frequency_hz == expected->frequency_hz)
        && (point->i_direct == expected->i_direct)
        && (point->q_direct == expected->q_direct)
        && (point->i_filtered == expected->i_filtered)
        && (point->q_filtered == expected->q_filtered);
}

static int reference_config_matches(const sweep_iq_config_t *config)
{
    return (config->point_count == SWEEP_IQ_DEFAULT_POINT_COUNT)
        && (config->first_frequency_hz
            == SWEEP_IQ_DEFAULT_FIRST_FREQ_HZ)
        && (config->frequency_step_hz
            == SWEEP_IQ_DEFAULT_FREQ_STEP_HZ)
        && (config->adc_sample_rate_hz
            == SWEEP_IQ_DEFAULT_ADC_SAMPLE_RATE_HZ);
}

static void print_point(const sweep_iq_point_t *point,
                        int check_available, int matches)
{
    xil_printf("index=%u, frequency=%u Hz\r\n",
               point->index, point->frequency_hz);
    xil_printf("  raw=0x%08x%08x\r\n",
               point->raw_high, point->raw_low);
    xil_printf("  direct : I=%d, Q=%d\r\n",
               (int)point->i_direct, (int)point->q_direct);
    xil_printf("  filtered: I=%d, Q=%d\r\n",
               (int)point->i_filtered, (int)point->q_filtered);
    if (check_available) {
        xil_printf("  reference check: %s\r\n\r\n",
                   matches ? "PASS" : "FAIL");
    } else {
        xil_printf("  reference check: N/A for this sweep configuration\r\n\r\n");
    }
}

static void print_selected_points(void)
{
    const sweep_iq_config_t *config = sweep_iq_get_config();
    u32 selected_indices[3];
    u32 i;
    u32 pass_count = 0U;
    int check_available = reference_config_matches(config);

    selected_indices[0] = 0U;
    selected_indices[1] = config->point_count / 2U;
    selected_indices[2] = config->point_count - 1U;

    xil_printf("\r\nBRAM IQ unpack test\r\n");
    xil_printf("Build: AXI latency 1, BRAM output register off\r\n");
    xil_printf("Sweep config: points=%u, first=%u Hz, step=%u Hz, fs=%u Hz\r\n",
               config->point_count, config->first_frequency_hz,
               config->frequency_step_hz, config->adc_sample_rate_hz);
    xil_printf("Checking first, middle and last valid sweep points.\r\n\r\n");

    for (i = 0U; i < 3U; ++i) {
        sweep_iq_point_t point;
        int status = sweep_iq_read_point(selected_indices[i], &point);
        int matches = 0;

        if (status != XST_SUCCESS) {
            xil_printf("Read failed at index %u, status=%d\r\n",
                       selected_indices[i], status);
            continue;
        }

        if (check_available) {
            matches = point_matches(&point, &expected_points[i]);
        }
        print_point(&point, check_available, matches);
        if (check_available && matches) {
            ++pass_count;
        }
    }

    if (check_available) {
        xil_printf("Summary: %u/3 reference points passed.\r\n", pass_count);
    } else {
        xil_printf("Summary: reference values are not defined for this sweep.\r\n");
    }

}

static int print_transfer_function_row(u32 index)
{
    sweep_iq_point_t iq;
    transfer_function_point_t transfer;
    u32 gain_per_mille;
    int status = sweep_iq_read_point(index, &iq);

    if (status == XST_SUCCESS) {
        status = transfer_function_calculate(&iq, &transfer);
    }
    if (status != XST_SUCCESS) {
        xil_printf("ERROR,index=%u,status=%d\r\n", index, status);
        return status;
    }

    gain_per_mille = (u32)((((u64)transfer.magnitude_q16 * 1000U)
                            + (TRANSFER_FUNCTION_Q_ONE / 2U))
                           / TRANSFER_FUNCTION_Q_ONE);
    xil_printf("%u,%d,%d,%u,%u\r\n",
               transfer.frequency_hz,
               (int)transfer.real_q16,
               (int)transfer.imag_q16,
               transfer.magnitude_q16,
               gain_per_mille);
    return XST_SUCCESS;
}

static void print_transfer_function_sweep(void)
{
    const sweep_iq_config_t *config = sweep_iq_get_config();
    u32 index_step = (config->point_count + TRANSFER_PRINT_TARGET_POINTS - 1U)
                   / TRANSFER_PRINT_TARGET_POINTS;
    u32 index;
    u32 emitted = 0U;
    u32 last_emitted_index = 0xFFFFFFFFU;

    xil_printf("\r\nH(jw) magnitude sweep CSV\r\n");
    xil_printf("Build: BRAM header + dynamic sweep + general real FIR fit v5\r\n");
    xil_printf("Q format: signed Q16.16 for real/imag, unsigned Q16.16 for magnitude.\r\n");
    xil_printf("frequency_hz,h_real_q16,h_imag_q16,magnitude_q16,gain_per_mille\r\n");

    for (index = 0U; index < config->point_count; index += index_step) {
        if (print_transfer_function_row(index) == XST_SUCCESS) {
            ++emitted;
            last_emitted_index = index;
        }
    }
    if (last_emitted_index != config->point_count - 1U) {
        if (print_transfer_function_row(config->point_count - 1U)
            == XST_SUCCESS) {
            ++emitted;
        }
    }

    xil_printf("H_SWEEP_END,points=%u,index_step=%u,frequency_step_hz=%u\r\n",
               emitted, index_step,
               index_step * config->frequency_step_hz);
    xil_printf("Press K3 / PS_KEY2 again to print another snapshot and sweep.\r\n");
}

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

static void coefficient_to_string(float coefficient, char *buffer)
{
    const u32 scale = 1000000000U;
    s64 rounded = (coefficient >= 0.0F)
                ? (s64)((double)coefficient * (double)scale + 0.5)
                : (s64)((double)coefficient * (double)scale - 0.5);
    u32 magnitude = (rounded < 0) ? (u32)(-rounded) : (u32)rounded;
    u32 whole = magnitude / scale;
    u32 fraction = magnitude % scale;
    u32 divisor = 100000000U;
    u32 position = 0U;

    if (rounded < 0) {
        buffer[position++] = '-';
    }
    buffer[position++] = (char)('0' + whole);
    buffer[position++] = '.';
    while (divisor != 0U) {
        buffer[position++] = (char)('0' + ((fraction / divisor) % 10U));
        divisor /= 10U;
    }
    buffer[position] = '\0';
}

static void generate_and_test_fir(void)
{
    const sweep_iq_config_t *sweep_config = sweep_iq_get_config();
    fir_fit_config_t config = {
        (double)sweep_config->adc_sample_rate_hz,
        FIR_FIT_TAP_COUNT,
        FIR_FIT_RIDGE_FACTOR
    };
    double measured_energy = 0.0;
    double residual_energy = 0.0;
    double phase_error_squared = 0.0;
    double dc_real;
    double dc_imag;
    double cutoff_target;
    u32 phase_point_count = 0U;
    u32 valid_point_count = 0U;
    u32 cutoff_hz = 0U;
    u32 index;
    int status;

    xil_printf("\r\nFloating FIR fit from measured H(jw)\r\n");
    xil_printf("Model: general real-coefficient %u-tap FIR, adc_fs=%u Hz, samples=%u, ridge=1e-6\r\n",
               FIR_FIT_TAP_COUNT, sweep_config->adc_sample_rate_hz,
               sweep_config->point_count);

    status = fir_fit_initialize(&fir_fit_workspace, &config);
    for (index = 0U; (index < sweep_config->point_count)
         && (status == FIR_FIT_SUCCESS); ++index) {
        sweep_iq_point_t iq;
        double response_real;
        double response_imag;

        status = sweep_iq_read_point(index, &iq);
        if (status != XST_SUCCESS) {
            break;
        }
        status = iq_to_complex_response(&iq, &response_real, &response_imag);
        if (status != XST_SUCCESS) {
            status = FIR_FIT_SUCCESS;
            continue;
        }
        status = fir_fit_add_sample(&fir_fit_workspace,
                                    (double)iq.frequency_hz,
                                    response_real, response_imag);
        if (status == FIR_FIT_SUCCESS) {
            ++valid_point_count;
        }
    }

    if (status == FIR_FIT_SUCCESS) {
        status = fir_fit_solve(&fir_fit_workspace, fitted_fir_coefficients,
                               FIR_FIT_TAP_COUNT);
    }
    if (status != FIR_FIT_SUCCESS) {
        xil_printf("FIR_FIT_ERROR,status=%d,valid_points=%u\r\n",
                   status, valid_point_count);
        return;
    }

    (void)fir_fit_evaluate(fitted_fir_coefficients, FIR_FIT_TAP_COUNT,
                           (double)sweep_config->adc_sample_rate_hz, 0.0,
                           &dc_real, &dc_imag);
    cutoff_target = hypot(dc_real, dc_imag) / sqrt(2.0);

    for (index = 0U; index < sweep_config->point_count; ++index) {
        sweep_iq_point_t iq;
        double measured_real;
        double measured_imag;
        double fitted_real;
        double fitted_imag;
        double measured_magnitude;
        double fitted_magnitude;
        double error_real;
        double error_imag;

        if (sweep_iq_read_point(index, &iq) != XST_SUCCESS
            || iq_to_complex_response(&iq, &measured_real,
                                      &measured_imag) != XST_SUCCESS
            || fir_fit_evaluate(fitted_fir_coefficients,
                                FIR_FIT_TAP_COUNT,
                                (double)sweep_config->adc_sample_rate_hz,
                                (double)iq.frequency_hz,
                                &fitted_real, &fitted_imag)
                                != FIR_FIT_SUCCESS) {
            continue;
        }

        error_real = measured_real - fitted_real;
        error_imag = measured_imag - fitted_imag;
        measured_magnitude = hypot(measured_real, measured_imag);
        fitted_magnitude = hypot(fitted_real, fitted_imag);
        measured_energy += measured_real * measured_real
                         + measured_imag * measured_imag;
        residual_energy += error_real * error_real
                         + error_imag * error_imag;

        if (measured_magnitude >= 0.01) {
            double phase_error = atan2(fitted_imag * measured_real
                                       - fitted_real * measured_imag,
                                       fitted_real * measured_real
                                       + fitted_imag * measured_imag);
            phase_error_squared += phase_error * phase_error;
            ++phase_point_count;
        }
        if ((cutoff_hz == 0U) && (fitted_magnitude <= cutoff_target)) {
            cutoff_hz = iq.frequency_hz;
        }
    }

    {
        double nrmse = sqrt(residual_energy / measured_energy);
        double phase_rmse_deg = sqrt(phase_error_squared
                                     / (double)phase_point_count)
                              * 57.29577951308232;
        u32 nrmse_ppm = (u32)(nrmse * 1000000.0 + 0.5);
        u32 phase_rmse_millideg =
            (u32)(phase_rmse_deg * 1000.0 + 0.5);
        xil_printf("FIR_FIT_RESULT,points=%u,nrmse_ppm=%u,phase_rmse_mdeg=%u,cutoff_hz=%u\r\n",
                   valid_point_count, nrmse_ppm,
                   phase_rmse_millideg, cutoff_hz);
    }

    xil_printf("tap_index,coefficient_float\r\n");
    for (index = 0U; index < FIR_FIT_TAP_COUNT; ++index) {
        char coefficient_text[16];
        coefficient_to_string(fitted_fir_coefficients[index],
                              coefficient_text);
        xil_printf("%u,%s\r\n", index, coefficient_text);
    }
    xil_printf("FIR_COEFFICIENTS_END,taps=%u\r\n", FIR_FIT_TAP_COUNT);
}

int main(void)
{
    ps_button_init();

    /*
     * Keep UART silent after JTAG download. This gives the user time to move
     * the only USB cable to the USB UART connector and open the COM port.
     */
    for (;;) {
        int status;
        const sweep_iq_header_t *header;

        ps_button_wait_for_press();
        status = sweep_iq_load_config_from_bram();
        header = sweep_iq_get_last_header();
        xil_printf("\r\nBRAM_CONFIG_RAW,magic=0x%08x,status=0x%08x,points=%u,first_hz=%u,step_hz=%u,adc_fs_hz=%u\r\n",
                   header->magic, header->status, header->point_count,
                   header->first_frequency_hz,
                   header->frequency_step_hz,
                   header->adc_sample_rate_hz);
        if (status != XST_SUCCESS) {
            xil_printf("\r\nBRAM_HEADER_ERROR,status=%d\r\n", status);
            xil_printf("Expected MAGIC=0x%08x and STATUS.DONE=1.\r\n",
                       SWEEP_IQ_HEADER_MAGIC);
            continue;
        }
        print_selected_points();
        print_transfer_function_sweep();
        generate_and_test_fir();
    }

    return XST_SUCCESS;
}
