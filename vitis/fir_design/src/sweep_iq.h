#ifndef SWEEP_IQ_H
#define SWEEP_IQ_H

#include "shared_bram_protocol.h"
#include "xil_types.h"

#define SWEEP_IQ_DEFAULT_FIRST_FREQ_HZ       200U
#define SWEEP_IQ_DEFAULT_LAST_FREQ_HZ        60000U
#define SWEEP_IQ_DEFAULT_FREQ_STEP_HZ        20U
#define SWEEP_IQ_DEFAULT_ADC_SAMPLE_RATE_HZ  300000U
#define SWEEP_IQ_DEFAULT_POINT_COUNT \
    (((SWEEP_IQ_DEFAULT_LAST_FREQ_HZ - SWEEP_IQ_DEFAULT_FIRST_FREQ_HZ) \
      / SWEEP_IQ_DEFAULT_FREQ_STEP_HZ) + 1U)

typedef struct {
    u32 point_count;
    u32 first_frequency_hz;
    u32 frequency_step_hz;
    u32 adc_sample_rate_hz;
} sweep_iq_config_t;

typedef struct {
    u32 index;
    u32 frequency_hz;
    u32 raw_direct;
    u32 raw_filtered;
    s16 i_direct;
    s16 q_direct;
    s16 i_filtered;
    s16 q_filtered;
} sweep_iq_point_t;

/* Poll and copy one stable measurement generation into PS-owned DDR. */
shared_bram_result_t sweep_iq_poll_snapshot(void);

const shared_bram_measurement_info_t *sweep_iq_get_measurement_info(void);
int sweep_iq_read_point(u32 index, sweep_iq_point_t *point);
int sweep_iq_configure(const sweep_iq_config_t *config);
const sweep_iq_config_t *sweep_iq_get_config(void);
u32 sweep_iq_get_capacity_points(void);

#endif
