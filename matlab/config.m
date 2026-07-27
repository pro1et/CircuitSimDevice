function cfg = config(runMode)
%CONFIG Central configuration for the circuit-learning simulation.
if nargin < 1
    runMode = "standard";
end

cfg.run_mode = string(runMode);
cfg.paths.root = fileparts(mfilename('fullpath'));
cfg.paths.results = fullfile(cfg.paths.root, 'results');

% Learning/sweep side (PL equivalent).
cfg.learn.fs = 30e6;
cfg.sweep.frequencies = (100:20:50000).';
cfg.sweep.cycles = 8;
cfg.sweep.chunk_samples = 32768;
cfg.sweep.dds_phase_bits = 32;
cfg.sweep.amplitude = 0.72;
cfg.sweep.debug_frequencies = [100 1000 10000 50000];
cfg.sweep.debug_max_samples = 180000;
cfg.sweep.convergence_windows = 32;
cfg.sweep.random_seed = 2025;

% Ordinary points use closed-form accumulated sufficient statistics.  The
% representative points use the exact chunked sample path for inspection.
cfg.sweep.ordinary_engine = "sufficient-statistics";
if cfg.run_mode == "streaming"
    cfg.sweep.ordinary_engine = "chunked";
end

% Converter models. Voltages are normalized to ADC full scale (+/-1).
cfg.dac.bits = 14;
cfg.dac.gain = 0.985;
cfg.dac.offset = 0.002;
cfg.dac.noise_rms = 1.5e-4;
cfg.adc.bits = 14;
cfg.adc.full_scale = 1.0;
cfg.adc.noise_rms = 2.0e-4;
cfg.adc.iq_payload_peak = 30000;

% Run-time FIR (ARM solve, then PL run-time filter).
cfg.fir.fs = 300e3;
cfg.fir.order = 128;
cfg.fir.tap_count = cfg.fir.order + 1;
cfg.fir.relative_floor = 0.04;
cfg.fir.ridge = 2e-5;
cfg.fir.smoothness = 2e-3;

% Time-domain verification.
cfg.verify.duration = 0.035;
cfg.verify.ignore_time = 0.004;
cfg.verify.time_tones = [400 2400 12000 38000];
cfg.output.save_figures = true;
cfg.output.figure_visible = 'off';
end
