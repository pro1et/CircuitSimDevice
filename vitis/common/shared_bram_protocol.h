#ifndef SHARED_BRAM_PROTOCOL_H
#define SHARED_BRAM_PROTOCOL_H

#include <stdint.h>
#include "xil_types.h"

#ifdef __cplusplus
extern "C" {
#endif

#define SHARED_BRAM_REG_MAGIC          0x00U
#define SHARED_BRAM_REG_VERSION        0x04U
#define SHARED_BRAM_REG_GENERATION     0x08U
#define SHARED_BRAM_REG_STATUS         0x0CU
#define SHARED_BRAM_REG_ARG0           0x10U
#define SHARED_BRAM_REG_FORMAT         0x14U
#define SHARED_BRAM_REG_ARG1           0x18U
#define SHARED_BRAM_PAYLOAD_OFFSET     0x40U

#ifndef SHARED_BRAM_MEAS_BASE_ADDRESS
#define SHARED_BRAM_MEAS_BASE_ADDRESS  0x40000000U
#endif
#ifndef SHARED_BRAM_COEFF_BASE_ADDRESS
#define SHARED_BRAM_COEFF_BASE_ADDRESS 0x40010000U
#endif
#define SHARED_BRAM_MEAS_SIZE_BYTES    (32U * 1024U)
#define SHARED_BRAM_COEFF_SIZE_BYTES   (4U * 1024U)

#define SHARED_BRAM_MEAS_MAGIC         0x4D454153U
#define SHARED_BRAM_COEFF_MAGIC        0x434F4546U
#define SHARED_BRAM_PROTOCOL_VERSION   0x00010000U

#define SHARED_BRAM_STATUS_STATE_MASK  0x00000003U
#define SHARED_BRAM_STATUS_BUSY        0x00000000U
#define SHARED_BRAM_MEAS_STATUS_DONE   0x00000001U
#define SHARED_BRAM_COEFF_STATUS_VALID 0x00000001U
#define SHARED_BRAM_STATUS_ERROR       0x00000002U

#define SHARED_BRAM_MEAS_STATUS_OVERFLOW  0x00000100U
#define SHARED_BRAM_MEAS_STATUS_TRUNCATED 0x00000200U

#define SHARED_BRAM_MEAS_FORMAT_IQ_INT16_X4 1U
#define SHARED_BRAM_COEFF_FORMAT_Q1_31      1U

/* IQ_INT16_X4 uses two words per sweep point:
 * word 0 = {I_direct[15:0], Q_direct[15:0]}
 * word 1 = {I_filtered[15:0], Q_filtered[15:0]}
 */
#define SHARED_BRAM_MEAS_WORDS_PER_IQ_POINT 2U

#define SHARED_BRAM_COEFF_ERROR_FIR_INITIALIZE 0x00000101U
#define SHARED_BRAM_COEFF_ERROR_IQ_READ        0x00000102U
#define SHARED_BRAM_COEFF_ERROR_TOO_FEW_POINTS 0x00000103U
#define SHARED_BRAM_COEFF_ERROR_FIR_SOLVE      0x00000104U
#define SHARED_BRAM_COEFF_ERROR_QUANTIZE       0x00000105U

typedef enum {
    SHARED_BRAM_OK = 0,
    SHARED_BRAM_NOT_READY = 1,
    SHARED_BRAM_RETRY = 2,
    SHARED_BRAM_INVALID_ARGUMENT = -1,
    SHARED_BRAM_BAD_MAGIC = -2,
    SHARED_BRAM_BAD_VERSION = -3,
    SHARED_BRAM_REMOTE_ERROR = -4,
    SHARED_BRAM_BAD_LENGTH = -5,
    SHARED_BRAM_BAD_FORMAT = -6
} shared_bram_result_t;

typedef struct {
    uint32_t generation;
    uint32_t status;
    uint32_t word_count;
    uint32_t format;
    uint32_t error_code;
} shared_bram_measurement_info_t;

void shared_bram_set_busy(UINTPTR base_address);

shared_bram_result_t shared_bram_read_measurement(
    UINTPTR base_address,
    uint32_t bram_size_bytes,
    uint32_t *destination,
    uint32_t destination_capacity_words,
    shared_bram_measurement_info_t *info);

shared_bram_result_t shared_bram_publish_coefficients_q31(
    UINTPTR base_address,
    uint32_t bram_size_bytes,
    const int32_t *coefficients,
    uint32_t tap_count,
    uint32_t *published_generation);

void shared_bram_publish_coefficient_error(
    UINTPTR base_address,
    uint32_t error_code,
    uint32_t *published_generation);

#ifdef __cplusplus
}
#endif

#endif
