#include "sweep_iq.h"

#include "xil_io.h"
#include "xparameters.h"
#include "xstatus.h"

static sweep_iq_config_t active_config = {
    SWEEP_IQ_DEFAULT_POINT_COUNT,
    SWEEP_IQ_DEFAULT_FIRST_FREQ_HZ,
    SWEEP_IQ_DEFAULT_FREQ_STEP_HZ,
    SWEEP_IQ_DEFAULT_ADC_SAMPLE_RATE_HZ
};

u32 sweep_iq_get_capacity_points(void)
{
    UINTPTR byte_count = (UINTPTR)XPAR_AXI_BRAM_CTRL_0_HIGHADDR
                       - (UINTPTR)XPAR_AXI_BRAM_CTRL_0_BASEADDR + 1U;
    return (u32)(byte_count / SWEEP_IQ_BYTES_PER_POINT);
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
    UINTPTR address;
    u32 low;
    u32 high;

    if ((point == NULL) || (index >= active_config.point_count)) {
        return XST_INVALID_PARAM;
    }

    address = (UINTPTR)XPAR_AXI_BRAM_CTRL_0_BASEADDR
            + ((UINTPTR)index * SWEEP_IQ_BYTES_PER_POINT);

    /*
     * Port A and the AXI BRAM controller are 32 bits wide. Each logical IQ
     * point occupies two adjacent words: direct first, then filtered.
     */
    low = Xil_In32(address);
    high = Xil_In32(address + 4U);

    point->index = index;
    point->frequency_hz = active_config.first_frequency_hz
                        + (active_config.frequency_step_hz * index);
    point->raw_low = low;
    point->raw_high = high;
    point->q_direct = (s16)(low & 0xFFFFU);
    point->i_direct = (s16)((low >> 16) & 0xFFFFU);
    point->q_filtered = (s16)(high & 0xFFFFU);
    point->i_filtered = (s16)((high >> 16) & 0xFFFFU);

    return XST_SUCCESS;
}
