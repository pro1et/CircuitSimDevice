%% Validate the floating-point FIR coefficients printed by the Vitis PS app
% This script uses only base MATLAB functions. It reconstructs the measured
% complex response from the original direct/filtered I/Q sweep, evaluates
% the supplied FIR at exactly the same frequencies, and compares both the
% magnitude and phase of H(jw).

clear; clc; close all;

script_dir = fileparts(mfilename('fullpath'));
input_file = fullfile(script_dir, 'sweep_iq_metadata.csv');
adc_sample_rate_hz = 250e3;

% Coefficients captured from the Vitis UART output, taps 0 through 128.
fir_coefficients = [
   -0.002035868
    0.008529259
   -0.016301801
    0.016988892
   -0.008006298
   -0.006572457
    0.009219076
   -0.001246740
   -0.007280017
    0.004401631
    0.005186470
   -0.004259490
   -0.001537698
    0.005570153
    0.000571767
   -0.005433030
   -0.000740666
    0.002564742
   -0.002960597
   -0.004782998
    0.001557752
    0.003791834
   -0.000435752
    0.000042992
    0.005174392
    0.004103086
   -0.001865682
   -0.002583394
   -0.000079914
   -0.002965024
   -0.007398145
   -0.004778075
    0.000718714
    0.001174118
    0.000800893
    0.005721439
    0.009814761
    0.006362939
    0.001171018
    0.000227034
   -0.001981177
   -0.009282989
   -0.013677321
   -0.009899773
   -0.004927488
   -0.002941069
    0.002742862
    0.013607843
    0.019369787
    0.015880341
    0.011329011
    0.007681497
   -0.003704895
   -0.021435754
   -0.031232456
   -0.029784292
   -0.027275926
   -0.021147901
    0.003956625
    0.043548133
    0.073709130
    0.093902014
    0.131618962
    0.187664598
    0.108261153
    0.187664598
    0.131618962
    0.093902014
    0.073709130
    0.043548133
    0.003956625
   -0.021147901
   -0.027275926
   -0.029784292
   -0.031232456
   -0.021435754
   -0.003704895
    0.007681497
    0.011329011
    0.015880341
    0.019369787
    0.013607843
    0.002742862
   -0.002941069
   -0.004927488
   -0.009899773
   -0.013677321
   -0.009282989
   -0.001981177
    0.000227034
    0.001171018
    0.006362939
    0.009814761
    0.005721439
    0.000800893
    0.001174118
    0.000718714
   -0.004778075
   -0.007398145
   -0.002965024
   -0.000079914
   -0.002583394
   -0.001865682
    0.004103086
    0.005174392
    0.000042992
   -0.000435752
    0.003791834
    0.001557752
   -0.004782998
   -0.002960597
    0.002564742
   -0.000740666
   -0.005433030
    0.000571767
    0.005570153
   -0.001537698
   -0.004259490
    0.005186470
    0.004401631
   -0.007280017
   -0.001246740
    0.009219076
   -0.006572457
   -0.008006298
    0.016988892
   -0.016301801
    0.008529259
   -0.002035868
];

%% Load measured complex H(jw)
data = readtable(input_file);
frequency_hz = double(data.frequency_hz(:));
x_direct = double(data.direct_i_int16(:)) ...
    + 1j * double(data.direct_q_int16(:));
y_filtered = double(data.filtered_i_int16(:)) ...
    + 1j * double(data.filtered_q_int16(:));
valid = isfinite(frequency_hz) & isfinite(real(x_direct)) ...
    & isfinite(imag(x_direct)) & (abs(x_direct) > 0);
frequency_hz = frequency_hz(valid);
h_measured = y_filtered(valid) ./ x_direct(valid);

%% Evaluate the supplied FIR without Signal Processing Toolbox
tap_index = 0:numel(fir_coefficients) - 1;
omega = 2 * pi * frequency_hz / adc_sample_rate_hz;
h_fir = exp(-1j * omega * tap_index) * fir_coefficients;
residual = h_measured - h_fir;

%% Metrics equivalent to the Vitis implementation
tap_count = numel(fir_coefficients);
fir_order = tap_count - 1;
symmetry_error = max(abs(fir_coefficients - flipud(fir_coefficients)));
dc_gain = abs(sum(fir_coefficients));
complex_rmse = sqrt(mean(abs(residual).^2));
complex_nrmse = complex_rmse / sqrt(mean(abs(h_measured).^2));

phase_mask = abs(h_measured) >= 0.01;
phase_error_deg = rad2deg(angle( ...
    h_fir(phase_mask) .* conj(h_measured(phase_mask))));
phase_rmse_deg = sqrt(mean(phase_error_deg.^2));

cutoff_target = dc_gain / sqrt(2);
cutoff_index = find(abs(h_fir) <= cutoff_target, 1, 'first');
if isempty(cutoff_index)
    cutoff_hz = NaN;
    cutoff_interpolated_hz = NaN;
elseif cutoff_index == 1
    cutoff_hz = frequency_hz(1);
    cutoff_interpolated_hz = cutoff_hz;
else
    cutoff_hz = frequency_hz(cutoff_index);
    f0 = frequency_hz(cutoff_index - 1);
    f1 = frequency_hz(cutoff_index);
    g0 = abs(h_fir(cutoff_index - 1));
    g1 = abs(h_fir(cutoff_index));
    cutoff_interpolated_hz = f0 + (cutoff_target - g0) ...
        * (f1 - f0) / (g1 - g0);
end

% Compare rounded metrics with the values printed by Vitis.
nrmse_ppm = round(complex_nrmse * 1e6);
phase_rmse_mdeg = round(phase_rmse_deg * 1e3);
reported_nrmse_ppm = 3813;
reported_phase_rmse_mdeg = 150;
reported_cutoff_hz = 19260;

checks = struct();
checks.tap_count = tap_count == 129;
checks.real_and_finite = isreal(fir_coefficients) ...
    && all(isfinite(fir_coefficients));
checks.symmetric = symmetry_error <= 1e-9;
checks.complex_nrmse = complex_nrmse < 0.005;
checks.phase_rmse = phase_rmse_deg < 0.25;
checks.cutoff = cutoff_hz >= 19000 && cutoff_hz <= 19500;
checks.matches_vitis = abs(nrmse_ppm - reported_nrmse_ppm) <= 2 ...
    && abs(phase_rmse_mdeg - reported_phase_rmse_mdeg) <= 1 ...
    && cutoff_hz == reported_cutoff_hz;
passed = all(structfun(@(value) logical(value), checks));

fprintf('Vitis FIR coefficient validation\n');
fprintf('  taps / order             : %d / %d\n', tap_count, fir_order);
fprintf('  symmetry error           : %.12g\n', symmetry_error);
fprintf('  DC gain                  : %.9f\n', dc_gain);
fprintf('  complex RMSE             : %.9g\n', complex_rmse);
fprintf('  complex NRMSE            : %.6f %% (%d ppm)\n', ...
    100 * complex_nrmse, nrmse_ppm);
fprintf('  phase RMSE above -40 dB  : %.6f deg (%d mdeg)\n', ...
    phase_rmse_deg, phase_rmse_mdeg);
fprintf('  -3 dB cutoff (grid)      : %.0f Hz\n', cutoff_hz);
fprintf('  -3 dB cutoff (interpol.) : %.3f Hz\n', cutoff_interpolated_hz);
fprintf('  matches Vitis metrics    : %s\n', pass_fail(checks.matches_vitis));
fprintf('  overall                  : %s\n', pass_fail(passed));

%% Save auditable point-by-point results
validation_table = table(frequency_hz, real(h_measured), imag(h_measured), ...
    abs(h_measured), 20 * log10(max(abs(h_measured), 1e-12)), ...
    real(h_fir), imag(h_fir), abs(h_fir), ...
    20 * log10(max(abs(h_fir), 1e-12)), abs(residual), ...
    'VariableNames', {'frequency_hz','measured_real','measured_imag', ...
    'measured_magnitude','measured_magnitude_db','fir_real','fir_imag', ...
    'fir_magnitude','fir_magnitude_db','complex_error'});
writetable(validation_table, ...
    fullfile(script_dir, 'vitis_fir_validation_samples.csv'));

coefficient_table = table((0:tap_count - 1).', fir_coefficients, ...
    'VariableNames', {'tap_index','coefficient_float'});
writetable(coefficient_table, ...
    fullfile(script_dir, 'vitis_fir_coefficients.csv'));

%% Visual comparison
figure('Color', 'w', 'Position', [100 100 1150 780]);
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot(frequency_hz, abs(h_measured), 'b', ...
    frequency_hz, abs(h_fir), 'r--', 'LineWidth', 1.1);
grid on; xlabel('Frequency (Hz)'); ylabel('|H|');
legend('Measured H', 'FIR H', 'Location', 'southwest');
title('Linear magnitude response');

nexttile;
plot(frequency_hz, 20 * log10(max(abs(h_measured), 1e-12)), 'b', ...
    frequency_hz, 20 * log10(max(abs(h_fir), 1e-12)), ...
    'r--', 'LineWidth', 1.1);
grid on; xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
legend('Measured H', 'FIR H', 'Location', 'southwest');
title('Log magnitude response'); ylim([-100 5]);

nexttile;
plot(frequency_hz(phase_mask), ...
    rad2deg(unwrap(angle(h_measured(phase_mask)))), 'b', ...
    frequency_hz(phase_mask), ...
    rad2deg(unwrap(angle(h_fir(phase_mask)))), ...
    'r--', 'LineWidth', 1.1);
grid on; xlabel('Frequency (Hz)'); ylabel('Phase (deg)');
legend('Measured H', 'FIR H', 'Location', 'southwest');
title('Phase where |H| >= -40 dB');

nexttile;
stem(tap_index, fir_coefficients, 'filled', 'MarkerSize', 2);
grid on; xlabel('Tap index'); ylabel('Coefficient');
title(sprintf('129-tap impulse response, symmetry error %.3g', ...
    symmetry_error));

exportgraphics(gcf, fullfile(script_dir, ...
    'vitis_fir_validation.png'), 'Resolution', 150);

if ~passed
    error('Vitis FIR coefficient validation failed.');
end

function text = pass_fail(value)
    if value
        text = 'PASS';
    else
        text = 'FAIL';
    end
end
