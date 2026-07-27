function results = main(runMode)
%MAIN Run PL sweep, ARM solve, and end-to-end verification.
%   RESULTS = MAIN() runs all 2496 frequency points. MAIN("streaming")
%   forces chunked sample generation at every point and is much slower.
if nargin < 1
    runMode = "standard";
end

root = fileparts(mfilename('fullpath'));
addpath(genpath(root));
cfg = config(runMode);
if ~exist(cfg.paths.results, 'dir')
    mkdir(cfg.paths.results);
end
rng(cfg.sweep.random_seed, 'twister');

fprintf('Circuit learning simulation: %d points, %.1f MHz learning Fs\n', ...
    numel(cfg.sweep.frequencies), cfg.learn.fs / 1e6);
circuit = create_circuit(cfg);

% PL owns the complete sweep and only publishes after the final point.
pl_snapshot = run_sweep(cfg, circuit);
assert(pl_snapshot.header.status == 1, 'PL snapshot was not published DONE.');

% ARM reads one stable batch, computes H, and solves one common tap vector.
response = calculate_response(cfg, pl_snapshot);
fir_solution = solve_fir(cfg, response);
coeff_snapshot = pack_coefficients(cfg, fir_solution);

sweep_metrics = verify_sweep(cfg, circuit, response);
fir_metrics = verify_fir(cfg, circuit, response, fir_solution);
plot_debug_signals(cfg, circuit, response, fir_solution, fir_metrics, pl_snapshot.debug);

results = struct('config', cfg, 'circuit', circuit, ...
    'pl_snapshot', pl_snapshot, 'response', response, ...
    'fir_solution', fir_solution, 'coeff_snapshot', coeff_snapshot, ...
    'sweep_metrics', sweep_metrics, 'fir_metrics', fir_metrics);
save(fullfile(cfg.paths.results, 'simulation_results.mat'), 'results', '-v7.3');

fprintf('Sweep: magnitude RMS %.3f dB, phase RMS %.3f deg\n', ...
    sweep_metrics.magnitude_rms_db, sweep_metrics.phase_rms_deg);
fprintf('FIR:   magnitude RMS %.3f dB, phase RMS %.3f deg\n', ...
    fir_metrics.magnitude_rms_db, fir_metrics.phase_rms_deg);
fprintf('Time:  NRMSE %.4f, correlation %.5f; Q1.31 saturated taps: %d\n', ...
    fir_metrics.time_nrmse, fir_metrics.time_correlation, ...
    coeff_snapshot.saturated_count);
fprintf('Results written to %s\n', cfg.paths.results);
end
