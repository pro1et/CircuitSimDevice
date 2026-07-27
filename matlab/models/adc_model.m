function codes = adc_model(cfg, x, addNoise)
%ADC_MODEL Signed ADC conversion returned as normalized floating-point codes.
if nargin < 3, addNoise = true; end
if addNoise
    x = x + cfg.adc.noise_rms * randn(size(x));
end
peak = 2^(cfg.adc.bits - 1) - 1;
x = min(max(x / cfg.adc.full_scale, -1), 1);
q = round(x * peak);
q = min(max(q, -peak-1), peak);
codes = q / peak;
end
