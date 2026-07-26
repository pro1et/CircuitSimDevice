%% Fit H(jw) from the two complex I/Q sweep channels
% Complex convention used by the FPGA DDC:
%   X = I_direct   + 1j * Q_direct
%   Y = I_filtered + 1j * Q_filtered
%   H(jw) = Y / X

% Fit a general real-coefficient FIR with complex least squares so both
% magnitude and phase participate in the fit. No toolbox is required.

clear; clc; close all;

script_dir = fileparts(mfilename('fullpath'));
input_file = fullfile(script_dir, 'sweep_iq_metadata.csv');

cfg.fs_hz = 300e3;
cfg.fit_taps = 129;
cfg.minimum_input_magnitude = 1000;
cfg.phase_error_minimum_gain = 1e-2;  % Ignore phase where H is below -40 dB.
cfg.ridge_factor = 1e-6;

data = readtable(input_file);
frequency_hz = double(data.frequency_hz(:));
x = double(data.direct_i_int16(:)) ...
    + 1j * double(data.direct_q_int16(:));
y = double(data.filtered_i_int16(:)) ...
    + 1j * double(data.filtered_q_int16(:));

valid = isfinite(frequency_hz) & isfinite(real(x)) & isfinite(imag(x)) ...
    & isfinite(real(y)) & isfinite(imag(y)) ...
    & (abs(x) >= cfg.minimum_input_magnitude);
if nnz(valid) < cfg.fit_taps
    error('Only %d valid points remain; at least %d are required.', ...
        nnz(valid), cfg.fit_taps);
end

frequency_hz = frequency_hz(valid);
x = x(valid);
y = y(valid);
h_measured = y ./ x;
omega = 2 * pi * frequency_hz / cfg.fs_hz;

%% General real-coefficient FIR complex least-squares fit
tap_index = 0:cfg.fit_taps - 1;
fit_matrix = exp(-1j * omega * tap_index);

% Stack real and imaginary equations so the fitted coefficients stay real.
real_system = [real(fit_matrix); imag(fit_matrix)];
real_target = [real(h_measured); imag(h_measured)];

% A very small ridge term stabilizes the partial-band FIR inversion without
% materially changing the response over the measured 200 Hz to 60 kHz band.
ridge = cfg.ridge_factor * trace(real_system.' * real_system) ...
    / size(real_system, 2);
fir_coefficients = (real_system.' * real_system ...
    + ridge * eye(size(real_system, 2))) ...
    \ (real_system.' * real_target);

h_fitted = fit_matrix * fir_coefficients;
residual = h_measured - h_fitted;

%% Fit metrics
complex_rmse = sqrt(mean(abs(residual).^2));
complex_nrmse = complex_rmse / sqrt(mean(abs(h_measured).^2));
phase_mask = abs(h_measured) >= cfg.phase_error_minimum_gain;
wrapped_phase_error_deg = rad2deg(angle( ...
    h_fitted(phase_mask) .* conj(h_measured(phase_mask))));
phase_rmse_deg = sqrt(mean(wrapped_phase_error_deg.^2));

passband_gain = median(abs(h_measured(frequency_hz <= 0.5e4)));
cutoff_target = passband_gain / sqrt(2);
cutoff_index = find(abs(h_fitted) <= cutoff_target, 1, 'first');
if isempty(cutoff_index)
    cutoff_hz = NaN;
else
    cutoff_hz = frequency_hz(cutoff_index);
end

fprintf('H(jw) fit points: %d\n', numel(frequency_hz));
fprintf('Model: general real-coefficient %d-tap FIR at %.0f Hz sample rate\n', ...
    cfg.fit_taps, cfg.fs_hz);
fprintf('Complex RMSE: %.6g\n', complex_rmse);
fprintf('Complex NRMSE: %.4f %%\n', 100 * complex_nrmse);
fprintf('Phase RMSE above -40 dB: %.4f deg\n', phase_rmse_deg);
fprintf('Estimated -3 dB cutoff: %.0f Hz\n', cutoff_hz);

%% Save numerical results for PS-side comparison
sample_table = table(frequency_hz, real(h_measured), imag(h_measured), ...
    abs(h_measured), 20 * log10(max(abs(h_measured), 1e-12)), ...
    rad2deg(unwrap(angle(h_measured))), real(h_fitted), imag(h_fitted), ...
    abs(h_fitted), 20 * log10(max(abs(h_fitted), 1e-12)), ...
    rad2deg(unwrap(angle(h_fitted))), abs(residual), ...
    'VariableNames', {'frequency_hz','h_real','h_imag','magnitude', ...
    'magnitude_db','phase_deg','fit_real','fit_imag','fit_magnitude', ...
    'fit_magnitude_db','fit_phase_deg','complex_error'});
writetable(sample_table, ...
    fullfile(script_dir, 'transfer_function_fit_samples.csv'));

coefficient_table = table((0:cfg.fit_taps - 1).', fir_coefficients, ...
    'VariableNames', {'tap_index','coefficient'});
writetable(coefficient_table, ...
    fullfile(script_dir, 'transfer_function_fir_coefficients.csv'));

%% Plot measured and fitted H(jw)
figure('Color', 'w', 'Position', [100 100 1100 760]);
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
plot(frequency_hz, 20 * log10(max(abs(h_measured), 1e-12)), ...
    'b', frequency_hz, 20 * log10(max(abs(h_fitted), 1e-12)), ...
    'r--', 'LineWidth', 1.0);
grid on; xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
legend('Measured H', 'Fitted H', 'Location', 'southwest');
title('H(j\omega) magnitude'); ylim([-100 5]);

nexttile;
plot(frequency_hz, rad2deg(unwrap(angle(h_measured))), ...
    'b', frequency_hz, rad2deg(unwrap(angle(h_fitted))), ...
    'r--', 'LineWidth', 1.0);
grid on; xlabel('Frequency (Hz)'); ylabel('Unwrapped phase (deg)');
legend('Measured H', 'Fitted H', 'Location', 'southwest');
title('H(j\omega) phase');

nexttile;
semilogy(frequency_hz, max(abs(residual), 1e-12), 'k', 'LineWidth', 1.0);
grid on; xlabel('Frequency (Hz)'); ylabel('|H_{measured}-H_{fit}|');
title(sprintf('Complex residual, NRMSE = %.3f %%', 100 * complex_nrmse));

nexttile;
plot(real(h_measured), imag(h_measured), 'b.', ...
    real(h_fitted), imag(h_fitted), 'r-', 'LineWidth', 1.0);
axis equal; grid on; xlabel('Real'); ylabel('Imaginary');
legend('Measured H', 'Fitted H', 'Location', 'best');
title('Complex-plane response');

exportgraphics(gcf, fullfile(script_dir, 'transfer_function_fit.png'), ...
    'Resolution', 150);
