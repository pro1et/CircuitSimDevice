function solution = solve_fir(cfg, response)
%SOLVE_FIR One real, non-symmetric FIR fit using the complete IQ batch.
valid = response.valid & isfinite(response.H);
f = response.actual_frequencies(valid);
target = response.H(valid);
M = cfg.fir.tap_count;
k = 0:M-1;
A = exp(-1j * 2*pi/cfg.fir.fs * (f * k));

% Relative weighting prevents the low-frequency, high-gain points from
% suppressing phase information in the attenuated part of the passband.
weight = 1 ./ max(abs(target), cfg.fir.relative_floor);
Aw = A .* weight;
bw = target .* weight;

D2 = diff(eye(M), 2, 1);
ridgeScale = sqrt(cfg.fir.ridge * size(Aw,1));
smoothScale = sqrt(cfg.fir.smoothness * size(Aw,1));
lhs = [real(Aw); imag(Aw); ridgeScale*eye(M); smoothScale*D2];
rhs = [real(bw); imag(bw); zeros(M,1); zeros(M-2,1)];
taps = lhs \ rhs;

solution.taps = taps(:).';
solution.order = cfg.fir.order;
solution.fs = cfg.fir.fs;
solution.fitted_frequencies = f;
solution.condition_estimate = cond(lhs);
solution.residual_norm = norm(A*taps-target) / norm(target);
solution.is_real = isreal(taps);
solution.is_symmetric = norm(taps-flipud(taps)) / max(norm(taps),eps) < 1e-6;
end
