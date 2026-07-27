function y = dac_model(cfg, x, addNoise)
%DAC_MODEL Normalized DAC gain, offset, quantization, and optional noise.
if nargin < 3, addNoise = true; end
levels = 2^(cfg.dac.bits - 1) - 1;
y = cfg.dac.gain * x + cfg.dac.offset;
y = min(max(y, -1), 1 - 1/levels);
y = round(y * levels) / levels;
if addNoise
    y = y + cfg.dac.noise_rms * randn(size(y));
end
end
