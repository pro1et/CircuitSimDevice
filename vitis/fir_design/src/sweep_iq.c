#include "sweep_iq.h"

#include "xstatus.h"

#include <stddef.h>

#define SWEEP_IQ_MAX_PAYLOAD_WORDS \
    ((SHARED_BRAM_MEAS_SIZE_BYTES - SHARED_BRAM_PAYLOAD_OFFSET) / 4U)

static sweep_iq_config_t active_config = {
    SWEEP_IQ_DEFAULT_POINT_COUNT,
    SWEEP_IQ_DEFAULT_FIRST_FREQ_HZ,
    SWEEP_IQ_DEFAULT_FREQ_STEP_HZ,
    SWEEP_IQ_DEFAULT_ADC_SAMPLE_RATE_HZ
};

/* A private snapshot prevents PL updates from changing data during FIR fit. */
static u32 measurement_snapshot[SWEEP_IQ_MAX_PAYLOAD_WORDS];
static shared_bram_measurement_info_t measurement_info;

u32 sweep_iq_get_capacity_points(void)
{
    return SWEEP_IQ_MAX_PAYLOAD_WORDS
         / SHARED_BRAM_MEAS_WORDS_PER_IQ_POINT;
}

shared_bram_result_t sweep_iq_poll_snapshot(void)
{
    sweep_iq_config_t config;
    shared_bram_result_t result = shared_bram_read_measurement(
        (UINTPTR)SHARED_BRAM_MEAS_BASE_ADDRESS,
        SHARED_BRAM_MEAS_SIZE_BYTES,
        measurement_snapshot,
        SWEEP_IQ_MAX_PAYLOAD_WORDS,
        &measurement_info);

    if (result != SHARED_BRAM_OK) {
        return result;
    }
    if ((measurement_info.word_count == 0U)
        || ((measurement_info.word_count
             % SHARED_BRAM_MEAS_WORDS_PER_IQ_POINT) != 0U)) {
        return SHARED_BRAM_BAD_LENGTH;
    }

    config.point_count = measurement_info.word_count
                       / SHARED_BRAM_MEAS_WORDS_PER_IQ_POINT;
    config.first_frequency_hz = SWEEP_IQ_DEFAULT_FIRST_FREQ_HZ;
    config.frequency_step_hz = SWEEP_IQ_DEFAULT_FREQ_STEP_HZ;
    config.adc_sample_rate_hz = SWEEP_IQ_DEFAULT_ADC_SAMPLE_RATE_HZ;

    if (sweep_iq_configure(&config) != XST_SUCCESS) {
        return SHARED_BRAM_BAD_LENGTH;
    }
    return SHARED_BRAM_OK;
}

const shared_bram_measurement_info_t *sweep_iq_get_measurement_info(void)
{
    return &measurement_info;
}

int sweep_iq_configure(const sweep_iq_config_t *config)
{
    u64 last_frequency_hz;

    if ((config == NULL) || (config->point_count == 0U)
        || (config->point_count > sweep_iq_get_capacity_points())
        || (config->frequency_step_hz == 0U)
        || (config->adc_sample_rate_hz == 0U)) {
        return XST_INVALID_PARAM;
    }

    last_frequency_hz = (u64)config->first_frequency_hz
                      + ((u64)(config->point_count - 1U)
                         * config->frequency_step_hz);
    if ((last_frequency_hz > 0xFFFFFFFFULL)
        || (last_frequency_hz * 2U > config->adc_sample_rate_hz)) {
        return XST_INVALID_PARAM;
    }

    active_config = *config;
    return XST_SUCCESS;
}

const sweep_iq_config_t *sweep_iq_get_config(void)
{
    return &active_config;
}

int sweep_iq_read_point(u32 index, sweep_iq_point_t *point)
{
    u32 direct;
    u32 filtered;
    u32 word_index;

    if ((point == NULL) || (index >= active_config.point_count)) {
        return XST_INVALID_PARAM;
    }

    word_index = index * SHARED_BRAM_MEAS_WORDS_PER_IQ_POINT;
    direct = measurement_snapshot[word_index];
    filtered = measurement_snapshot[word_index + 1U];

    point->index = index;
    point->frequency_hz = active_config.first_frequency_hz
                        + (active_config.frequency_step_hz * index);
    point->raw_direct = direct;
    point->raw_filtered = filtered;
    point->q_direct = (s16)(direct & 0xFFFFU);
    point->i_direct = (s16)((direct >> 16) & 0xFFFFU);
    point->q_filtered = (s16)(filtered & 0xFFFFU);
    point->i_filtered = (s16)((filtered >> 16) & 0xFFFFU);

    return XST_SUCCESS;
}
