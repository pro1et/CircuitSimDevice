function metrics = verify_fir(cfg, circuit, response, solution)
%VERIFY_FIR Frequency- and time-domain DUT versus learned FIR comparison.
f = response.actual_frequencies;
target = circuit.response(f); target = target(:);
A = exp(-1j * 2*pi/cfg.fir.fs * (f * (0:cfg.fir.order)));
Hfir = A * solution.taps(:);
valid = response.valid & abs(target) > 1e-5;
ratio = Hfir(valid) ./ target(valid);
magError = 20*log10(max(abs(ratio), realmin));
phaseError = angle(ratio) * 180/pi;

fs = cfg.fir.fs;
t = (0:1/fs:cfg.verify.duration-1/fs).';
x = zeros(size(t));
amps = [0.30 0.25 0.18 0.12];
for k = 1:numel(cfg.verify.time_tones)
    x = x + amps(k)*sin(2*pi*cfg.verify.time_tones(k)*t + 0.37*k);
end
% Add a short, band-limited chirp segment to exercise nonstationary behavior.
x = x + 0.12*chirp(t, 300, t(end), 45000, 'logarithmic');
x = 0.8*x/max(abs(x));
sysd = c2d(circuit.sys, 1/fs, 'tustin');
[bd, ad] = tfdata(sysd, 'v');
yDut = filter(bd, ad, x);
yFir = filter(solution.taps, 1, x);
use = t >= cfg.verify.ignore_time;
err = yFir(use) - yDut(use);

metrics.magnitude_rms_db = sqrt(mean(magError.^2));
metrics.magnitude_max_db = max(abs(magError));
metrics.phase_rms_deg = sqrt(mean(phaseError.^2));
metrics.phase_max_deg = max(abs(phaseError));
metrics.time_nrmse = rms(err) / rms(yDut(use));
C = corrcoef(yDut(use), yFir(use));
metrics.time_correlation = C(1,2);
metrics.frequency_response = Hfir;
metrics.time = t;
metrics.input = x;
metrics.dut_output = yDut;
metrics.fir_output = yFir;
end
