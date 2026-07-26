#ifndef FIR_FIT_H
#define FIR_FIT_H

#include <stddef.h>

#define FIR_FIT_MAX_TAPS             129U
#define FIR_FIT_MAX_UNIQUE_COEFFS    ((FIR_FIT_MAX_TAPS + 1U) / 2U)

typedef struct {
    double sample_rate_hz;
    unsigned int tap_count;
    double ridge_factor;
} fir_fit_config_t;

typedef struct {
    fir_fit_config_t config;
    unsigned int unique_coefficient_count;
    unsigned int sample_count;
    double normal_matrix[FIR_FIT_MAX_UNIQUE_COEFFS]
                        [FIR_FIT_MAX_UNIQUE_COEFFS];
    double right_hand_side[FIR_FIT_MAX_UNIQUE_COEFFS];
} fir_fit_workspace_t;

enum {
    FIR_FIT_SUCCESS = 0,
    FIR_FIT_INVALID_ARGUMENT = -1,
    FIR_FIT_INSUFFICIENT_SAMPLES = -2,
    FIR_FIT_SINGULAR_MATRIX = -3
};

int fir_fit_initialize(fir_fit_workspace_t *workspace,
                       const fir_fit_config_t *config);

int fir_fit_add_sample(fir_fit_workspace_t *workspace,
                       double frequency_hz,
                       double response_real,
                       double response_imag);

int fir_fit_solve(fir_fit_workspace_t *workspace,
                  float *coefficients,
                  size_t coefficient_capacity);

int fir_fit_evaluate(const float *coefficients,
                     unsigned int tap_count,
                     double sample_rate_hz,
                     double frequency_hz,
                     double *response_real,
                     double *response_imag);

#endif
