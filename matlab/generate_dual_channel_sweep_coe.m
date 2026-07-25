%% Dual-channel sweep data model for FPGA BRAM
% Generates deterministic, ADC-like direct and filtered sweep captures.
% No Signal Processing Toolbox is required.
%
% Output word layout (all COE files use radix 16 and 32-bit words):
%   sweep_frequency_hz.coe : uint32 frequency in Hz, padded to BRAM depth.
%   sweep_adc_capture.coe  : [31:16] filtered int16, [15:0] direct int16.
%
% The capture file preserves the two's-complement bit pattern used by a
% 16-bit ADC.  The remaining BRAM words are explicitly written as zero.

clear; clc;

%% Sweep and ADC configuration
cfg.f_start_hz = 200;
cfg.f_stop_hz  = 60000;
cfg.f_step_hz  = 20;
cfg.frequency_hz = (cfg.f_start_hz:cfg.f_step_hz:cfg.f_stop_hz).';
cfg.bram_depth_words = 4096;

cfg.adc_sample_rate_hz = 250e3;      % Fs: safely above 2 x 60 kHz
cfg.adc_bits = 16;
cfg.adc_full_scale_code = 2^(cfg.adc_bits - 1) - 1;
cfg.samples_per_point = 4096;        % 16.384 ms dwell / frequency point
cfg.input_peak_fs = 0.72;            % primary tone: 72 %% of ADC full scale
cfg.second_harmonic_peak_fs = 0.015; % realistic source distortion
cfg.noise_rms_lsb = 5;               % ADC + front-end noise, in ADC LSB
cfg.rng_seed = 20260725;

%% Digital filter under test: 129-tap, 20 kHz low-pass FIR
% This is a practical anti-alias / response-shaping model.  The coefficients
% are calculated locally with a Hamming window so no toolbox is required.
cfg.filter_type = '129-tap Hamming-windowed low-pass FIR';
cfg.filter_cutoff_hz = 20e3;
cfg.filter_taps = 129;
h = design_lowpass_fir(cfg.filter_taps, cfg.filter_cutoff_hz, ...
                       cfg.adc_sample_rate_hz);

%% Generate realistic steady-state ADC observations at every sweep frequency
rng(cfg.rng_seed, 'twister');
point_count = numel(cfg.frequency_hz);
if point_count > cfg.bram_depth_words
    error('Sweep has %d points but BRAM depth is only %d words.', ...
        point_count, cfg.bram_depth_words);
end
direct_capture = zeros(point_count, 1, 'int16');
filtered_capture = zeros(point_count, 1, 'int16');
direct_rms = zeros(point_count, 1, 'uint16');
filtered_rms = zeros(point_count, 1, 'uint16');
direct_rms_float = zeros(point_count, 1);
filtered_rms_float = zeros(point_count, 1);

n = (0:cfg.samples_per_point - 1).';
for k = 1:point_count
    f0 = cfg.frequency_hz(k);

    % Frequency response of the actual finite FIR, including phase.
    h1 = fir_response(h, f0, cfg.adc_sample_rate_hz);
    h2 = fir_response(h, 2 * f0, cfg.adc_sample_rate_hz);

    % The direct path includes source harmonic distortion and ADC noise.
    % The filter path applies the FIR response independently to both tones.
    phase1 = 2 * pi * f0 * n / cfg.adc_sample_rate_hz + 0.37;
    phase2 = 2 * pi * (2 * f0) * n / cfg.adc_sample_rate_hz - 0.91;
    direct_normalized = cfg.input_peak_fs * sin(phase1) + ...
        cfg.second_harmonic_peak_fs * sin(phase2) + ...
        (cfg.noise_rms_lsb / cfg.adc_full_scale_code) * randn(size(n));
    filtered_normalized = cfg.input_peak_fs * abs(h1) * ...
        sin(phase1 + angle(h1)) + ...
        cfg.second_harmonic_peak_fs * abs(h2) * sin(phase2 + angle(h2)) + ...
        (cfg.noise_rms_lsb / cfg.adc_full_scale_code) * randn(size(n));

    direct_samples = quantize_adc(direct_normalized, cfg.adc_full_scale_code);
    filtered_samples = quantize_adc(filtered_normalized, cfg.adc_full_scale_code);

    % One raw sample is retained per sweep point for a compact BRAM capture.
    direct_capture(k) = direct_samples(end);
    filtered_capture(k) = filtered_samples(end);

    % This reproduces the fixed-point FPGA magnitude pipeline conceptually:
    % ADC int16 -> square -> accumulate -> mean -> integer square root.
    direct_rms_float(k) = sqrt(mean(double(direct_samples).^2));
    filtered_rms_float(k) = sqrt(mean(double(filtered_samples).^2));
    direct_rms(k) = uint16(min(round(direct_rms_float(k)), 65535));
    filtered_rms(k) = uint16(min(round(filtered_rms_float(k)), 65535));
end

%% Pack data exactly as it will be represented in a 32-bit FPGA BRAM word
frequency_words = pad_bram_words(uint32(cfg.frequency_hz), cfg.bram_depth_words);
adc_words = pad_bram_words(pack_int16_pair(direct_capture, filtered_capture), ...
    cfg.bram_depth_words);

%% Write COE files next to this script
output_dir = fileparts(mfilename('fullpath'));
write_coe(fullfile(output_dir, 'sweep_frequency_hz.coe'), frequency_words);
write_coe(fullfile(output_dir, 'sweep_adc_capture.coe'), adc_words);

metadata = table(cfg.frequency_hz, direct_capture, filtered_capture, ...
    direct_rms, filtered_rms, direct_rms_float, filtered_rms_float, ...
    'VariableNames', {'frequency_hz', 'direct_adc_int16', ...
    'filtered_adc_int16', 'direct_rms_uint16', 'filtered_rms_uint16', ...
    'direct_rms_float', 'filtered_rms_float'});
writetable(metadata, fullfile(output_dir, 'sweep_metadata.csv'));

%% Produce a verification figure for MATLAB-side inspection
figure('Color', 'w', 'Name', 'Dual-channel FPGA sweep model');
plot(cfg.frequency_hz, direct_rms_float, 'b', 'LineWidth', 1.1); hold on;
plot(cfg.frequency_hz, filtered_rms_float, 'r', 'LineWidth', 1.1);
grid on;
xlabel('Frequency (Hz)');
ylabel('RMS ADC codes');
legend('Direct ADC path', 'Filtered ADC path', 'Location', 'northeast');
title(sprintf('20 Hz sweep, %s, f_c = %.0f Hz', ...
    cfg.filter_type, cfg.filter_cutoff_hz));
exportgraphics(gcf, fullfile(output_dir, 'dual_channel_sweep_response.png'), ...
    'Resolution', 150);

fprintf('Generated %d sweep points from %d Hz to %d Hz.\n', ...
    point_count, cfg.f_start_hz, cfg.f_stop_hz);
fprintf('Each COE file is zero-padded to %d 32-bit BRAM words.\n', ...
    cfg.bram_depth_words);
fprintf('COE files written to: %s\n', output_dir);

function h = design_lowpass_fir(tap_count, cutoff_hz, fs_hz)
    if mod(tap_count, 2) == 0
        error('tap_count must be odd for a linear-phase FIR.');
    end
    if cutoff_hz <= 0 || cutoff_hz >= fs_hz / 2
        error('cutoff_hz must be between 0 and Nyquist.');
    end
    m = (tap_count - 1) / 2;
    index = -m:m;
    normalized_cutoff = cutoff_hz / fs_hz;
    ideal = 2 * normalized_cutoff * sinc(2 * normalized_cutoff * index);
    hamming_window = 0.54 - 0.46 * cos(2 * pi * (0:tap_count - 1) / (tap_count - 1));
    h = ideal .* hamming_window;
    h = h / sum(h);                  % unity DC gain
end

function response = fir_response(h, frequency_hz, fs_hz)
    sample_index = 0:numel(h) - 1;
    response = sum(h .* exp(-1j * 2 * pi * frequency_hz * sample_index / fs_hz));
end

function samples = quantize_adc(normalized_signal, full_scale_code)
    clipped = min(max(normalized_signal, -1), 1 - 1 / full_scale_code);
    samples = int16(round(clipped * full_scale_code));
end

function words = pack_int16_pair(low_half_int16, high_half_int16)
    % typecast retains the ADC's two's-complement bits; numeric conversion
    % would instead clamp negative signed values to zero.
    low_bits = typecast(low_half_int16(:), 'uint16');
    high_bits = typecast(high_half_int16(:), 'uint16');
    words = bitor(uint32(low_bits), bitshift(uint32(high_bits), 16));
end

function padded_words = pad_bram_words(words, bram_depth_words)
    words = uint32(words(:));
    if numel(words) > bram_depth_words
        error('Input has %d words, exceeding BRAM depth %d.', ...
            numel(words), bram_depth_words);
    end
    padded_words = [words; zeros(bram_depth_words - numel(words), 1, 'uint32')];
end

function write_coe(filename, words)
    fid = fopen(filename, 'w');
    if fid < 0
        error('Unable to create %s', filename);
    end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '; Generated by generate_dual_channel_sweep_coe.m\n');
    fprintf(fid, 'memory_initialization_radix=16;\n');
    fprintf(fid, 'memory_initialization_vector=\n');
    hex_words = upper(dec2hex(uint32(words(:)), 8));
    for index = 1:size(hex_words, 1)
        terminator = ',';
        if index == size(hex_words, 1)
            terminator = ';';
        end
        fprintf(fid, '%s%s\n', hex_words(index, :), terminator);
    end
end
