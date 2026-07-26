#include "fir_fit.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

#define FIR_FIT_TWO_PI  6.283185307179586476925286766559

static int config_is_valid(const fir_fit_config_t *config)
{
    return (config != NULL)
        && (config->sample_rate_hz > 0.0)
        && (config->tap_count >= 3U)
        && (config->tap_count <= FIR_FIT_MAX_TAPS)
        && ((config->tap_count & 1U) != 0U)
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
    workspace->unique_coefficient_count = (config->tap_count + 1U) / 2U;
    return FIR_FIT_SUCCESS;
}

int fir_fit_add_sample(fir_fit_workspace_t *workspace,
                       double frequency_hz,
                       double response_real,
                       double response_imag)
{
    double basis[FIR_FIT_MAX_UNIQUE_COEFFS];
    double omega;
    double center_phase;
    double rotated_response_real;
    unsigned int center;
    unsigned int unique_count;
    unsigned int row;
    unsigned int column;

    if ((workspace == NULL) || !config_is_valid(&workspace->config)
        || (frequency_hz < 0.0)
        || (frequency_hz > workspace->config.sample_rate_hz / 2.0)
        || !isfinite(response_real) || !isfinite(response_imag)) {
        return FIR_FIT_INVALID_ARGUMENT;
    }

    center = (workspace->config.tap_count - 1U) / 2U;
    unique_count = workspace->unique_coefficient_count;
    omega = FIR_FIT_TWO_PI * frequency_hz
          / workspace->config.sample_rate_hz;
    center_phase = omega * (double)center;

    /*
     * For a real symmetric FIR:
     * H(w) = exp(-j*w*M) * (h[M] + 2*sum(h[M-k]*cos(w*k))).
     * The bracketed expression is real, reducing 129 unknown taps to 65.
     */
    basis[0] = 1.0;
    for (column = 1U; column < unique_count; ++column) {
        basis[column] = 2.0 * cos(omega * (double)column);
    }

    rotated_response_real = cos(center_phase) * response_real
                          - sin(center_phase) * response_imag;

    for (row = 0U; row < unique_count; ++row) {
        workspace->right_hand_side[row] +=
            basis[row] * rotated_response_real;
        for (column = 0U; column <= row; ++column) {
            workspace->normal_matrix[row][column] +=
                basis[row] * basis[column];
        }
    }

    ++workspace->sample_count;
    return FIR_FIT_SUCCESS;
}

static int solve_normal_equations(fir_fit_workspace_t *workspace,
                                  double *solution)
{
    unsigned int count = workspace->unique_coefficient_count;
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
    double solution[FIR_FIT_MAX_UNIQUE_COEFFS] = {0.0};
    unsigned int center;
    unsigned int offset;
    int status;

    if ((workspace == NULL) || (coefficients == NULL)
        || !config_is_valid(&workspace->config)
        || (coefficient_capacity < workspace->config.tap_count)) {
        return FIR_FIT_INVALID_ARGUMENT;
    }
    if (workspace->sample_count < workspace->unique_coefficient_count) {
        return FIR_FIT_INSUFFICIENT_SAMPLES;
    }

    status = solve_normal_equations(workspace, solution);
    if (status != FIR_FIT_SUCCESS) {
        return status;
    }

    center = (workspace->config.tap_count - 1U) / 2U;
    coefficients[center] = (float)solution[0];
    for (offset = 1U; offset <= center; ++offset) {
        float coefficient = (float)solution[offset];
        coefficients[center - offset] = coefficient;
        coefficients[center + offset] = coefficient;
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
    double amplitude;
    unsigned int center;
    unsigned int offset;

    if ((coefficients == NULL) || (response_real == NULL)
        || (response_imag == NULL) || (sample_rate_hz <= 0.0)
        || (tap_count < 3U) || (tap_count > FIR_FIT_MAX_TAPS)
        || ((tap_count & 1U) == 0U) || (frequency_hz < 0.0)
        || (frequency_hz > sample_rate_hz / 2.0)) {
        return FIR_FIT_INVALID_ARGUMENT;
    }

    center = (tap_count - 1U) / 2U;
    omega = FIR_FIT_TWO_PI * frequency_hz / sample_rate_hz;
    amplitude = (double)coefficients[center];
    for (offset = 1U; offset <= center; ++offset) {
        amplitude += 2.0 * (double)coefficients[center - offset]
                   * cos(omega * (double)offset);
    }

    *response_real = amplitude * cos(omega * (double)center);
    *response_imag = -amplitude * sin(omega * (double)center);
    return FIR_FIT_SUCCESS;
}
