#include "fir_fit.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define TEST_TAPS       129U
#define TEST_SAMPLE_RATE_HZ  300000.0

static int run_variable_sweep_test(unsigned int point_count,
                                   double first_frequency_hz,
                                   double frequency_step_hz)
{
    enum { SYNTHETIC_TAPS = 33 };
    static fir_fit_workspace_t workspace;
    float reference[SYNTHETIC_TAPS];
    float fitted[SYNTHETIC_TAPS];
    fir_fit_config_t config = {
        TEST_SAMPLE_RATE_HZ, SYNTHETIC_TAPS, 1e-10
    };
    double measured_energy = 0.0;
    double residual_energy = 0.0;
    unsigned int index;
    int status;

    /* Deliberately asymmetric impulse response verifies the general model. */
    for (index = 0U; index < SYNTHETIC_TAPS; ++index) {
        reference[index] = (float)(pow(0.82, (double)index)
                         * (0.13 + 0.04 * sin(0.71 * (double)index)));
    }

    status = fir_fit_initialize(&workspace, &config);
    for (index = 0U; (index < point_count)
         && (status == FIR_FIT_SUCCESS); ++index) {
        double frequency_hz = first_frequency_hz
                            + frequency_step_hz * index;
        double response_real;
        double response_imag;
        status = fir_fit_evaluate(reference, SYNTHETIC_TAPS,
                                  TEST_SAMPLE_RATE_HZ, frequency_hz,
                                  &response_real, &response_imag);
        if (status == FIR_FIT_SUCCESS) {
            status = fir_fit_add_sample(&workspace, frequency_hz,
                                        response_real, response_imag);
        }
    }
    if (status == FIR_FIT_SUCCESS) {
        status = fir_fit_solve(&workspace, fitted, SYNTHETIC_TAPS);
    }
    if (status != FIR_FIT_SUCCESS) {
        return status;
    }

    for (index = 0U; index < point_count; ++index) {
        double frequency_hz = first_frequency_hz
                            + frequency_step_hz * index;
        double measured_real;
        double measured_imag;
        double fitted_real;
        double fitted_imag;
        double error_real;
        double error_imag;
        (void)fir_fit_evaluate(reference, SYNTHETIC_TAPS,
                               TEST_SAMPLE_RATE_HZ, frequency_hz,
                               &measured_real, &measured_imag);
        (void)fir_fit_evaluate(fitted, SYNTHETIC_TAPS,
                               TEST_SAMPLE_RATE_HZ, frequency_hz,
                               &fitted_real, &fitted_imag);
        error_real = measured_real - fitted_real;
        error_imag = measured_imag - fitted_imag;
        measured_energy += measured_real * measured_real
                         + measured_imag * measured_imag;
        residual_energy += error_real * error_real
                         + error_imag * error_imag;
    }

    {
        double nrmse = sqrt(residual_energy / measured_energy);
        printf("variable_sweep_points=%u,first_hz=%.0f,step_hz=%.0f,nrmse=%.9g\n",
               point_count, first_frequency_hz, frequency_step_hz, nrmse);
        return (nrmse < 1e-5) ? FIR_FIT_SUCCESS : 1;
    }
}

int main(int argc, char **argv)
{
    static fir_fit_workspace_t workspace;
    float coefficients[TEST_TAPS];
    fir_fit_config_t config = {TEST_SAMPLE_RATE_HZ, TEST_TAPS, 1e-6};
    FILE *input;
    char header[256];
    unsigned int sample_count = 0U;
    double measured_energy = 0.0;
    double residual_energy = 0.0;
    double cutoff_hz = 0.0;
    double dc_real;
    double dc_imag;
    double cutoff_target;
    int status;

    if (argc != 2) {
        fprintf(stderr, "usage: fir_fit_host_test sweep_iq_metadata.csv\n");
        return 2;
    }
    input = fopen(argv[1], "r");
    if (input == NULL || fgets(header, sizeof(header), input) == NULL) {
        fprintf(stderr, "unable to read input CSV\n");
        return 2;
    }

    status = fir_fit_initialize(&workspace, &config);
    while (status == FIR_FIT_SUCCESS) {
        double frequency_hz;
        int direct_i;
        int direct_q;
        int filtered_i;
        int filtered_q;
        double direct_magnitude;
        double filtered_magnitude;
        double denominator;
        double response_real;
        double response_imag;
        int fields = fscanf(input, "%lf,%d,%d,%d,%d,%lf,%lf",
                            &frequency_hz, &direct_i, &direct_q,
                            &filtered_i, &filtered_q,
                            &direct_magnitude, &filtered_magnitude);
        (void)direct_magnitude;
        (void)filtered_magnitude;
        if (fields == EOF) {
            break;
        }
        if (fields != 7) {
            fprintf(stderr, "malformed CSV row after sample %u\n",
                    sample_count);
            fclose(input);
            return 2;
        }
        denominator = (double)direct_i * direct_i
                    + (double)direct_q * direct_q;
        response_real = ((double)filtered_i * direct_i
                         + (double)filtered_q * direct_q) / denominator;
        response_imag = ((double)filtered_q * direct_i
                         - (double)filtered_i * direct_q) / denominator;
        status = fir_fit_add_sample(&workspace, frequency_hz,
                                    response_real, response_imag);
        ++sample_count;
    }
    fclose(input);

    if (status == FIR_FIT_SUCCESS) {
        status = fir_fit_solve(&workspace, coefficients, TEST_TAPS);
    }
    if (status != FIR_FIT_SUCCESS) {
        fprintf(stderr, "fit failed: %d\n", status);
        return 1;
    }

    status = fir_fit_evaluate(coefficients, TEST_TAPS,
                              TEST_SAMPLE_RATE_HZ, 0.0,
                              &dc_real, &dc_imag);
    cutoff_target = hypot(dc_real, dc_imag) / sqrt(2.0);

    input = fopen(argv[1], "r");
    if (input == NULL || fgets(header, sizeof(header), input) == NULL) {
        return 2;
    }
    while (status == FIR_FIT_SUCCESS) {
        double frequency_hz;
        int direct_i;
        int direct_q;
        int filtered_i;
        int filtered_q;
        double ignored_direct_magnitude;
        double ignored_filtered_magnitude;
        double denominator;
        double measured_real;
        double measured_imag;
        double fitted_real;
        double fitted_imag;
        double error_real;
        double error_imag;
        int fields = fscanf(input, "%lf,%d,%d,%d,%d,%lf,%lf",
                            &frequency_hz, &direct_i, &direct_q,
                            &filtered_i, &filtered_q,
                            &ignored_direct_magnitude,
                            &ignored_filtered_magnitude);
        if (fields == EOF) {
            break;
        }
        if (fields != 7) {
            fclose(input);
            return 2;
        }
        denominator = (double)direct_i * direct_i
                    + (double)direct_q * direct_q;
        measured_real = ((double)filtered_i * direct_i
                         + (double)filtered_q * direct_q) / denominator;
        measured_imag = ((double)filtered_q * direct_i
                         - (double)filtered_i * direct_q) / denominator;
        status = fir_fit_evaluate(coefficients, TEST_TAPS,
                                  TEST_SAMPLE_RATE_HZ, frequency_hz,
                                  &fitted_real, &fitted_imag);
        error_real = measured_real - fitted_real;
        error_imag = measured_imag - fitted_imag;
        measured_energy += measured_real * measured_real
                         + measured_imag * measured_imag;
        residual_energy += error_real * error_real
                         + error_imag * error_imag;
        if ((cutoff_hz == 0.0)
            && (hypot(fitted_real, fitted_imag) <= cutoff_target)) {
            cutoff_hz = frequency_hz;
        }
    }
    fclose(input);

    {
        double nrmse = sqrt(residual_energy / measured_energy);
        printf("samples=%u\n", sample_count);
        printf("nrmse=%.9f\n", nrmse);
        printf("cutoff_hz=%.0f\n", cutoff_hz);
        printf("dc_gain=%.9f\n", hypot(dc_real, dc_imag));
        printf("center_coefficient=%.9f\n", coefficients[TEST_TAPS / 2U]);

        if (sample_count != 2991U || nrmse >= 0.005
            || cutoff_hz < 19000.0 || cutoff_hz > 19500.0
            || !isfinite(coefficients[TEST_TAPS / 2U])) {
            fprintf(stderr, "FIR fit acceptance test failed\n");
            return 1;
        }
    }

    if (run_variable_sweep_test(401U, 100.0, 300.0)
        != FIR_FIT_SUCCESS
        || run_variable_sweep_test(173U, 250.0, 700.0)
           != FIR_FIT_SUCCESS) {
        fprintf(stderr, "variable sweep test failed\n");
        return 1;
    }

    puts("PASS");
    return 0;
}
