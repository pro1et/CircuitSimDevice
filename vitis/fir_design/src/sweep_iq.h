#ifndef SWEEP_IQ_H
#define SWEEP_IQ_H

#include "xil_types.h"

#define SWEEP_IQ_DEFAULT_FIRST_FREQ_HZ  200U
#define SWEEP_IQ_DEFAULT_LAST_FREQ_HZ   60000U
#define SWEEP_IQ_DEFAULT_FREQ_STEP_HZ   20U
#define SWEEP_IQ_DEFAULT_ADC_SAMPLE_RATE_HZ 3001U
#define SWEEP_IQ_DEFAULT_POINT_COUNT \
    (((SWEEP_IQ_DEFAULT_LAST_FREQ_HZ - SWEEP_IQ_DEFAULT_FIRST_FREQ_HZ) \
      / SWEEP_IQ_DEFAULT_FREQ_STEP_HZ) + 1U)
#define SWEEP_IQ_BYTES_PER_POINT        8U
#define SWEEP_IQ_HEADER_WORD_COUNT      6U
#define SWEEP_IQ_HEADER_BYTES           (SWEEP_IQ_HEADER_WORD_COUNT * 4U)
#define SWEEP_IQ_HEADER_MAGIC           0x53574550U
#define SWEEP_IQ_STATUS_DONE_MASK       0x00000001U

#define SWEEP_IQ_HEADER_MAGIC_OFFSET       0U
#define SWEEP_IQ_HEADER_STATUS_OFFSET      4U
#define SWEEP_IQ_HEADER_POINT_COUNT_OFFSET 8U
#define SWEEP_IQ_HEADER_FIRST_FREQ_OFFSET  12U
#define SWEEP_IQ_HEADER_FREQ_STEP_OFFSET   16U
#define SWEEP_IQ_HEADER_ADC_FS_OFFSET      20U

typedef struct {
    u32 point_count;
    u32 first_frequency_hz;
    u32 frequency_step_hz;
    u32 adc_sample_rate_hz;
} sweep_iq_config_t;

typedef struct {
    u32 magic;
    u32 status;
    u32 point_count;
    u32 first_frequency_hz;
    u32 frequency_step_hz;
    u32 adc_sample_rate_hz;
} sweep_iq_header_t;

typedef struct {
    u32 index;
    u32 frequency_hz;
    u32 raw_low;
    u32 raw_high;
    s16 i_direct;
    s16 q_direct;
    s16 i_filtered;
    s16 q_filtered;
} sweep_iq_point_t;

int sweep_iq_read_point(u32 index, sweep_iq_point_t *point);
int sweep_iq_load_config_from_bram(void);
const sweep_iq_header_t *sweep_iq_get_last_header(void);
int sweep_iq_configure(const sweep_iq_config_t *config);
const sweep_iq_config_t *sweep_iq_get_config(void);
u32 sweep_iq_get_capacity_points(void);

#endif
