%% Dual physical-channel I/Q sweep model for FPGA BRAM initialization
% Models analog signal -> 16-bit ADC -> FPGA-style DDC -> I/Q COE results.
% direct COE:   [31:16] I_direct,   [15:0] Q_direct
% filtered COE: [31:16] I_filtered, [15:0] Q_filtered
% complete COE: [63:48] I_filtered, [47:32] Q_filtered,
%               [31:16] I_direct,   [15:0] Q_direct

clear; clc;

%% Configuration
cfg.f_start_hz = 200;
cfg.f_stop_hz = 60000;
cfg.f_step_hz = 20;
cfg.frequency_hz = (cfg.f_start_hz:cfg.f_step_hz:cfg.f_stop_hz).';
cfg.bram_depth_words = 4096;
cfg.fs_hz = 250e3;
cfg.adc_full_scale = 32767;
cfg.samples_per_point = 4096;
cfg.input_peak_fs = 0.72;
cfg.harmonic_peak_fs = 0.015;
cfg.noise_rms_lsb = 5;
cfg.filter_cutoff_hz = 20e3;
cfg.filter_taps = 129;

if numel(cfg.frequency_hz) > cfg.bram_depth_words
    error('Sweep point count exceeds BRAM depth.');
end

% 129-tap Hamming-windowed FIR low-pass model for the filtered path.
h = lowpass_fir(cfg.filter_taps, cfg.filter_cutoff_hz, cfg.fs_hz);
rng(20260725, 'twister');
count = numel(cfg.frequency_hz);
direct_i = zeros(count, 1, 'int16');
direct_q = zeros(count, 1, 'int16');
filtered_i = zeros(count, 1, 'int16');
filtered_q = zeros(count, 1, 'int16');
n = (0:cfg.samples_per_point - 1).';

%% ADC capture simulation and FPGA DDC simulation
for k = 1:count
    f0 = cfg.frequency_hz(k);
    h1 = fir_response(h, f0, cfg.fs_hz);
    h2 = fir_response(h, 2 * f0, cfg.fs_hz);
    phase1 = 2 * pi * f0 * n / cfg.fs_hz + 0.37;
    phase2 = 2 * pi * 2 * f0 * n / cfg.fs_hz - 0.91;

    direct_norm = cfg.input_peak_fs * sin(phase1) + ...
        cfg.harmonic_peak_fs * sin(phase2) + ...
        cfg.noise_rms_lsb / cfg.adc_full_scale * randn(size(n));
    filtered_norm = cfg.input_peak_fs * abs(h1) * sin(phase1 + angle(h1)) + ...
        cfg.harmonic_peak_fs * abs(h2) * sin(phase2 + angle(h2)) + ...
        cfg.noise_rms_lsb / cfg.adc_full_scale * randn(size(n));

    direct_adc = quantize_adc(direct_norm, cfg.adc_full_scale);
    filtered_adc = quantize_adc(filtered_norm, cfg.adc_full_scale);
    [direct_i(k), direct_q(k)] = ddc_iq(direct_adc, f0, cfg);
    [filtered_i(k), filtered_q(k)] = ddc_iq(filtered_adc, f0, cfg);
end

%% Pack data and pad every COE to 4096 frequency-point words
frequency_words = pad_words(uint32(cfg.frequency_hz), cfg.bram_depth_words);
direct_words_raw = pack_iq(direct_i, direct_q);
filtered_words_raw = pack_iq(filtered_i, filtered_q);
complete_words_raw = pack_complete_iq(filtered_i, filtered_q, direct_i, direct_q);
direct_words = pad_words(direct_words_raw, cfg.bram_depth_words);
filtered_words = pad_words(filtered_words_raw, cfg.bram_depth_words);
complete_words = pad_words(complete_words_raw, cfg.bram_depth_words);
out_dir = fileparts(mfilename('fullpath'));
write_coe(fullfile(out_dir, 'sweep_frequency_hz.coe'), frequency_words, 8);
write_coe(fullfile(out_dir, 'sweep_iq_direct.coe'), direct_words, 8);
write_coe(fullfile(out_dir, 'sweep_iq_filtered.coe'), filtered_words, 8);
write_coe(fullfile(out_dir, 'sweep_iq_complete.coe'), complete_words, 16);

direct_mag = hypot(double(direct_i), double(direct_q));
filtered_mag = hypot(double(filtered_i), double(filtered_q));
metadata = table(cfg.frequency_hz, direct_i, direct_q, filtered_i, filtered_q, ...
    direct_mag, filtered_mag, 'VariableNames', ...
    {'frequency_hz','direct_i_int16','direct_q_int16','filtered_i_int16', ...
     'filtered_q_int16','direct_iq_magnitude','filtered_iq_magnitude'});
writetable(metadata, fullfile(out_dir, 'sweep_iq_metadata.csv'));

figure('Color', 'w');
plot(cfg.frequency_hz, direct_mag, 'b', cfg.frequency_hz, filtered_mag, 'r', 'LineWidth', 1.1);
grid on; xlabel('Frequency (Hz)'); ylabel('I/Q magnitude (ADC Q1.15 codes)');
legend('Direct channel', 'Filtered channel', 'Location', 'northeast');
title('Dual physical-channel FPGA DDC model');
exportgraphics(gcf, fullfile(out_dir, 'dual_channel_iq_response.png'), 'Resolution', 150);

fprintf('Generated %d I/Q points; all COEs are padded to %d words.\n', ...
    count, cfg.bram_depth_words);

function h = lowpass_fir(taps, cutoff_hz, fs_hz)
    m = (taps - 1) / 2;
    index = -m:m;
    fc = cutoff_hz / fs_hz;
    h = 2 * fc * sinc(2 * fc * index);
    h = h .* (0.54 - 0.46 * cos(2 * pi * (0:taps - 1) / (taps - 1)));
    h = h / sum(h);
end

function value = fir_response(h, frequency_hz, fs_hz)
    index = 0:numel(h) - 1;
    value = sum(h .* exp(-1j * 2 * pi * frequency_hz * index / fs_hz));
end

function adc = quantize_adc(signal, full_scale)
    signal = min(max(signal, -1), 1 - 1 / full_scale);
    adc = int16(round(signal * full_scale));
end

function [i_code, q_code] = ddc_iq(adc, frequency_hz, cfg)
    index = (0:numel(adc) - 1).';
    phase = 2 * pi * frequency_hz * index / cfg.fs_hz;
    cos_nco = int16(round(cfg.adc_full_scale * cos(phase)));
    minus_sin_nco = int16(round(-cfg.adc_full_scale * sin(phase)));
    scale = numel(adc) * cfg.adc_full_scale;
    i_code = saturate_int16(round(double(sum(int64(adc) .* int64(cos_nco))) / scale));
    q_code = saturate_int16(round(double(sum(int64(adc) .* int64(minus_sin_nco))) / scale));
end

function value = saturate_int16(value)
    value = int16(min(max(value, -32768), 32767));
end

function words = pack_iq(i_code, q_code)
    i_bits = typecast(i_code(:), 'uint16');
    q_bits = typecast(q_code(:), 'uint16');
    words = bitor(bitshift(uint32(i_bits), 16), uint32(q_bits));
end

function words = pack_complete_iq(filtered_i, filtered_q, direct_i, direct_q)
    filtered_i_bits = uint64(typecast(filtered_i(:), 'uint16'));
    filtered_q_bits = uint64(typecast(filtered_q(:), 'uint16'));
    direct_i_bits = uint64(typecast(direct_i(:), 'uint16'));
    direct_q_bits = uint64(typecast(direct_q(:), 'uint16'));
    words = bitor(bitshift(filtered_i_bits, 48), bitshift(filtered_q_bits, 32));
    words = bitor(words, bitshift(direct_i_bits, 16));
    words = bitor(words, direct_q_bits);
end

function padded = pad_words(words, depth)
    words = words(:);
    padded = [words; zeros(depth - numel(words), 1, 'like', words)];
end

function write_coe(filename, words, hex_width)
    fid = fopen(filename, 'w');
    if fid < 0, error('Unable to create %s', filename); end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '; Generated by generate_dual_channel_sweep_coe.m\n');
    fprintf(fid, 'memory_initialization_radix=16;\n');
    fprintf(fid, 'memory_initialization_vector=\n');
    hex_words = upper(dec2hex(words(:), hex_width));
    for k = 1:size(hex_words, 1)
        suffix = ',';
        if k == size(hex_words, 1), suffix = ';'; end
        fprintf(fid, '%s%s\n', hex_words(k, :), suffix);
    end
end
