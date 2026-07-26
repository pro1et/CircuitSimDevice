#include "shared_bram_protocol.h"

#include "xil_io.h"

static uint32_t shared_bram_read32(UINTPTR base_address, uint32_t offset)
{
    return Xil_In32(base_address + (UINTPTR)offset);
}

static void shared_bram_write32(
    UINTPTR base_address,
    uint32_t offset,
    uint32_t value)
{
    Xil_Out32(base_address + (UINTPTR)offset, value);
}

static void shared_bram_memory_barrier(void)
{
#if defined(__arm__) || defined(__aarch64__)
    __asm__ volatile("dmb sy" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}

void shared_bram_set_busy(UINTPTR base_address)
{
    shared_bram_write32(
        base_address,
        SHARED_BRAM_REG_STATUS,
        SHARED_BRAM_STATUS_BUSY);
    shared_bram_memory_barrier();
}

shared_bram_result_t shared_bram_read_measurement(
    UINTPTR base_address,
    uint32_t bram_size_bytes,
    uint32_t *destination,
    uint32_t destination_capacity_words,
    shared_bram_measurement_info_t *info)
{
    uint32_t generation_before;
    uint32_t generation_confirm;
    uint32_t generation_after;
    uint32_t status_before;
    uint32_t status_confirm;
    uint32_t status_after;
    uint32_t max_payload_words;
    uint32_t index;

    if ((destination == (uint32_t *)0)
        || (info == (shared_bram_measurement_info_t *)0)
        || (bram_size_bytes < SHARED_BRAM_PAYLOAD_OFFSET)) {
        return SHARED_BRAM_INVALID_ARGUMENT;
    }

    status_before = shared_bram_read32(
        base_address,
        SHARED_BRAM_REG_STATUS);

    if ((status_before & SHARED_BRAM_STATUS_STATE_MASK)
        == SHARED_BRAM_STATUS_BUSY) {
        return SHARED_BRAM_NOT_READY;
    }

    if ((status_before & SHARED_BRAM_STATUS_STATE_MASK)
        == SHARED_BRAM_STATUS_ERROR) {
        info->error_code = shared_bram_read32(
            base_address,
            SHARED_BRAM_REG_ARG1);
        return SHARED_BRAM_REMOTE_ERROR;
    }

    if ((status_before & SHARED_BRAM_STATUS_STATE_MASK)
        != SHARED_BRAM_MEAS_STATUS_DONE) {
        return SHARED_BRAM_NOT_READY;
    }

    if (shared_bram_read32(base_address, SHARED_BRAM_REG_MAGIC)
        != SHARED_BRAM_MEAS_MAGIC) {
        return SHARED_BRAM_BAD_MAGIC;
    }

    if (shared_bram_read32(base_address, SHARED_BRAM_REG_VERSION)
        != SHARED_BRAM_PROTOCOL_VERSION) {
        return SHARED_BRAM_BAD_VERSION;
    }

    generation_before = shared_bram_read32(
        base_address,
        SHARED_BRAM_REG_GENERATION);

    status_confirm = shared_bram_read32(
        base_address,
        SHARED_BRAM_REG_STATUS);
    generation_confirm = shared_bram_read32(
        base_address,
        SHARED_BRAM_REG_GENERATION);

    if ((generation_confirm != generation_before)
        || ((status_confirm & SHARED_BRAM_STATUS_STATE_MASK)
            != SHARED_BRAM_MEAS_STATUS_DONE)) {
        return SHARED_BRAM_RETRY;
    }

    info->generation = generation_confirm;
    info->status = status_before;
    info->word_count = shared_bram_read32(
        base_address,
        SHARED_BRAM_REG_ARG0);
    info->format = shared_bram_read32(
        base_address,
        SHARED_BRAM_REG_FORMAT);
    info->error_code = shared_bram_read32(
        base_address,
        SHARED_BRAM_REG_ARG1);

    max_payload_words =
        (bram_size_bytes - SHARED_BRAM_PAYLOAD_OFFSET) / 4U;

    if ((info->word_count == 0U)
        || (info->word_count > max_payload_words)
        || (info->word_count > destination_capacity_words)) {
        return SHARED_BRAM_BAD_LENGTH;
    }

    if (info->format != SHARED_BRAM_MEAS_FORMAT_IQ_INT16_X4) {
        return SHARED_BRAM_BAD_FORMAT;
    }

    for (index = 0U; index < info->word_count; ++index) {
        destination[index] = shared_bram_read32(
            base_address,
            SHARED_BRAM_PAYLOAD_OFFSET + (4U * index));
    }

    shared_bram_memory_barrier();

    generation_after = shared_bram_read32(
        base_address,
        SHARED_BRAM_REG_GENERATION);
    status_after = shared_bram_read32(
        base_address,
        SHARED_BRAM_REG_STATUS);

    if ((generation_after != generation_confirm)
        || ((status_after & SHARED_BRAM_STATUS_STATE_MASK)
            != SHARED_BRAM_MEAS_STATUS_DONE)) {
        return SHARED_BRAM_RETRY;
    }

    return SHARED_BRAM_OK;
}

shared_bram_result_t shared_bram_publish_coefficients_q31(
    UINTPTR base_address,
    uint32_t bram_size_bytes,
    const int32_t *coefficients,
    uint32_t tap_count,
    uint32_t *published_generation)
{
    uint32_t max_payload_words;
    uint32_t generation;
    uint32_t index;
    uint32_t offset;

    if ((coefficients == (const int32_t *)0)
        || (tap_count == 0U)
        || (bram_size_bytes < SHARED_BRAM_PAYLOAD_OFFSET)) {
        return SHARED_BRAM_INVALID_ARGUMENT;
    }

    max_payload_words =
        (bram_size_bytes - SHARED_BRAM_PAYLOAD_OFFSET) / 4U;
    if (tap_count > max_payload_words) {
        return SHARED_BRAM_BAD_LENGTH;
    }

    generation = shared_bram_read32(
        base_address,
        SHARED_BRAM_REG_GENERATION);

    // BUSY is zero by design and must be published before any other update.
    shared_bram_set_busy(base_address);

    shared_bram_write32(
        base_address,
        SHARED_BRAM_REG_MAGIC,
        SHARED_BRAM_COEFF_MAGIC);
    shared_bram_write32(
        base_address,
        SHARED_BRAM_REG_VERSION,
        SHARED_BRAM_PROTOCOL_VERSION);
    shared_bram_write32(
        base_address,
        SHARED_BRAM_REG_ARG0,
        tap_count);
    shared_bram_write32(
        base_address,
        SHARED_BRAM_REG_FORMAT,
        SHARED_BRAM_COEFF_FORMAT_Q1_31);
    shared_bram_write32(
        base_address,
        SHARED_BRAM_REG_ARG1,
        31U);

    for (offset = 0x1CU;
         offset < SHARED_BRAM_PAYLOAD_OFFSET;
         offset += 4U) {
        shared_bram_write32(base_address, offset, 0U);
    }

    for (index = 0U; index < tap_count; ++index) {
        shared_bram_write32(
            base_address,
            SHARED_BRAM_PAYLOAD_OFFSET + (4U * index),
            (uint32_t)coefficients[index]);
    }

    shared_bram_memory_barrier();

    generation += 1U;
    shared_bram_write32(
        base_address,
        SHARED_BRAM_REG_GENERATION,
        generation);

    shared_bram_memory_barrier();

    shared_bram_write32(
        base_address,
        SHARED_BRAM_REG_STATUS,
        SHARED_BRAM_COEFF_STATUS_VALID);

    shared_bram_memory_barrier();

    if (published_generation != (uint32_t *)0) {
        *published_generation = generation;
    }

    return SHARED_BRAM_OK;
}

void shared_bram_publish_coefficient_error(
    UINTPTR base_address,
    uint32_t error_code,
    uint32_t *published_generation)
{
    uint32_t generation = shared_bram_read32(
        base_address,
        SHARED_BRAM_REG_GENERATION);
    uint32_t offset;

    shared_bram_set_busy(base_address);
    shared_bram_write32(
        base_address, SHARED_BRAM_REG_MAGIC, SHARED_BRAM_COEFF_MAGIC);
    shared_bram_write32(
        base_address, SHARED_BRAM_REG_VERSION,
        SHARED_BRAM_PROTOCOL_VERSION);
    shared_bram_write32(base_address, SHARED_BRAM_REG_ARG0, 0U);
    shared_bram_write32(
        base_address, SHARED_BRAM_REG_FORMAT,
        SHARED_BRAM_COEFF_FORMAT_Q1_31);

    /* ARG1 is SCALE while VALID and an error code while STATUS is ERROR. */
    shared_bram_write32(base_address, SHARED_BRAM_REG_ARG1, error_code);
    for (offset = 0x1CU;
         offset < SHARED_BRAM_PAYLOAD_OFFSET;
         offset += 4U) {
        shared_bram_write32(base_address, offset, 0U);
    }

    shared_bram_memory_barrier();
    generation += 1U;
    shared_bram_write32(
        base_address, SHARED_BRAM_REG_GENERATION, generation);
    shared_bram_memory_barrier();
    shared_bram_write32(
        base_address, SHARED_BRAM_REG_STATUS, SHARED_BRAM_STATUS_ERROR);
    shared_bram_memory_barrier();

    if (published_generation != (uint32_t *)0) {
        *published_generation = generation;
    }
}
