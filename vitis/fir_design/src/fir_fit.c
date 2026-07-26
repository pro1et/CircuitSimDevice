#include "fir_fit.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

#define FIR_FIT_TWO_PI  6.283185307179586476925286766559

static int config_is_valid(const fir_fit_config_t *config)
{
    return (config != NULL)
        && (config->sample_rate_hz > 0.0)
        && (config->tap_count >= 1U)
        && (config->tap_count <= FIR_FIT_MAX_TAPS)
        && (config->ridge_factor >= 0.0);
}

int fir_fit_initialize(fir_fit_workspace_t *workspace,
                       const fir_fit_config_t *config)
{
    if ((workspace == NULL) || !config_is_valid(config)) {
        return FIR_FIT_INVALID_ARGUMENT;
    }

    memset(workspace, 0, sizeof(*workspace));
    workspace->config = *config;
    workspace->coefficient_count = config->tap_count;
    return FIR_FIT_SUCCESS;
}

int fir_fit_add_sample(fir_fit_workspace_t *workspace,
                       double frequency_hz,
                       double response_real,
                       double response_imag)
{
    double basis_real[FIR_FIT_MAX_TAPS];
    double basis_imag[FIR_FIT_MAX_TAPS];
    double omega;
    double cosine;
    double sine;
    unsigned int coefficient_count;
    unsigned int row;
    unsigned int column;

    if ((workspace == NULL) || !config_is_valid(&workspace->config)
        || (frequency_hz < 0.0)
        || (frequency_hz > workspace->config.sample_rate_hz / 2.0)
        || !isfinite(response_real) || !isfinite(response_imag)) {
        return FIR_FIT_INVALID_ARGUMENT;
    }

    coefficient_count = workspace->coefficient_count;
    omega = FIR_FIT_TWO_PI * frequency_hz
          / workspace->config.sample_rate_hz;

    /*
     * General real-coefficient FIR:
     * H(w) = sum(h[n] * exp(-j*w*n)).  Stack the real and imaginary
     * equations implicitly.  Each measured complex response contributes
     * A_real^T*A_real + A_imag^T*A_imag to the real normal matrix.
     */
    cosine = cos(omega);
    sine = sin(omega);
    basis_real[0] = 1.0;
    basis_imag[0] = 0.0;
    for (column = 1U; column < coefficient_count; ++column) {
        double previous_real = basis_real[column - 1U];
        double previous_imag = basis_imag[column - 1U];
        basis_real[column] = previous_real * cosine
                           + previous_imag * sine;
        basis_imag[column] = previous_imag * cosine
                           - previous_real * sine;
    }

    for (row = 0U; row < coefficient_count; ++row) {
        workspace->right_hand_side[row] +=
            basis_real[row] * response_real
          + basis_imag[row] * response_imag;
        for (column = 0U; column <= row; ++column) {
            workspace->normal_matrix[row][column] +=
                basis_real[row] * basis_real[column]
              + basis_imag[row] * basis_imag[column];
        }
    }

    ++workspace->sample_count;
    return FIR_FIT_SUCCESS;
}

static int solve_normal_equations(fir_fit_workspace_t *workspace,
                                  double *solution)
{
    unsigned int count = workspace->coefficient_count;
    unsigned int row;
    unsigned int column;
    unsigned int pivot_column;
    double diagonal_mean = 0.0;
    double ridge;

    for (row = 0U; row < count; ++row) {
        for (column = row + 1U; column < count; ++column) {
            workspace->normal_matrix[row][column] =
                workspace->normal_matrix[column][row];
        }
        diagonal_mean += workspace->normal_matrix[row][row];
    }
    diagonal_mean /= (double)count;
    ridge = workspace->config.ridge_factor * diagonal_mean;
    for (row = 0U; row < count; ++row) {
        workspace->normal_matrix[row][row] += ridge;
    }

    for (pivot_column = 0U; pivot_column < count; ++pivot_column) {
        unsigned int pivot_row = pivot_column;
        double pivot_magnitude =
            fabs(workspace->normal_matrix[pivot_row][pivot_column]);

        for (row = pivot_column + 1U; row < count; ++row) {
            double candidate =
                fabs(workspace->normal_matrix[row][pivot_column]);
            if (candidate > pivot_magnitude) {
                pivot_magnitude = candidate;
                pivot_row = row;
            }
        }

        if (pivot_magnitude <= 1e-18 * diagonal_mean) {
            return FIR_FIT_SINGULAR_MATRIX;
        }

        if (pivot_row != pivot_column) {
            for (column = pivot_column; column < count; ++column) {
                double temporary =
                    workspace->normal_matrix[pivot_column][column];
                workspace->normal_matrix[pivot_column][column] =
                    workspace->normal_matrix[pivot_row][column];
                workspace->normal_matrix[pivot_row][column] = temporary;
            }
            {
                double temporary = workspace->right_hand_side[pivot_column];
                workspace->right_hand_side[pivot_column] =
                    workspace->right_hand_side[pivot_row];
                workspace->right_hand_side[pivot_row] = temporary;
            }
        }

        for (row = pivot_column + 1U; row < count; ++row) {
            double factor = workspace->normal_matrix[row][pivot_column]
                          / workspace->normal_matrix[pivot_column][pivot_column];
            workspace->normal_matrix[row][pivot_column] = 0.0;
            for (column = pivot_column + 1U; column < count; ++column) {
                workspace->normal_matrix[row][column] -= factor
                    * workspace->normal_matrix[pivot_column][column];
            }
            workspace->right_hand_side[row] -=
                factor * workspace->right_hand_side[pivot_column];
        }
    }

    for (row = count; row-- > 0U;) {
        double value = workspace->right_hand_side[row];
        for (column = row + 1U; column < count; ++column) {
            value -= workspace->normal_matrix[row][column] * solution[column];
        }
        solution[row] = value / workspace->normal_matrix[row][row];
    }

    return FIR_FIT_SUCCESS;
}

int fir_fit_solve(fir_fit_workspace_t *workspace,
                  float *coefficients,
                  size_t coefficient_capacity)
{
    double solution[FIR_FIT_MAX_TAPS] = {0.0};
    unsigned int tap;
    int status;

    if ((workspace == NULL) || (coefficients == NULL)
        || !config_is_valid(&workspace->config)
        || (coefficient_capacity < workspace->config.tap_count)) {
        return FIR_FIT_INVALID_ARGUMENT;
    }
    if (workspace->sample_count < workspace->coefficient_count) {
        return FIR_FIT_INSUFFICIENT_SAMPLES;
    }

    status = solve_normal_equations(workspace, solution);
    if (status != FIR_FIT_SUCCESS) {
        return status;
    }

    for (tap = 0U; tap < workspace->coefficient_count; ++tap) {
        coefficients[tap] = (float)solution[tap];
    }
    return FIR_FIT_SUCCESS;
}

int fir_fit_evaluate(const float *coefficients,
                     unsigned int tap_count,
                     double sample_rate_hz,
                     double frequency_hz,
                     double *response_real,
                     double *response_imag)
{
    double omega;
    double basis_real = 1.0;
    double basis_imag = 0.0;
    double cosine;
    double sine;
    double real = 0.0;
    double imag = 0.0;
    unsigned int tap;

    if ((coefficients == NULL) || (response_real == NULL)
        || (response_imag == NULL) || (sample_rate_hz <= 0.0)
        || (tap_count < 1U) || (tap_count > FIR_FIT_MAX_TAPS)
        || (frequency_hz < 0.0)
        || (frequency_hz > sample_rate_hz / 2.0)) {
        return FIR_FIT_INVALID_ARGUMENT;
    }

    omega = FIR_FIT_TWO_PI * frequency_hz / sample_rate_hz;
    cosine = cos(omega);
    sine = sin(omega);
    for (tap = 0U; tap < tap_count; ++tap) {
        double previous_real;
        real += (double)coefficients[tap] * basis_real;
        imag += (double)coefficients[tap] * basis_imag;
        previous_real = basis_real;
        basis_real = basis_real * cosine + basis_imag * sine;
        basis_imag = basis_imag * cosine - previous_real * sine;
    }

    *response_real = real;
    *response_imag = imag;
    return FIR_FIT_SUCCESS;
}
