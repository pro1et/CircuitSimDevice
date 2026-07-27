function [iq, debug] = iq_accumulate(cfg, circuit, frequency, keepDebug)
%IQ_ACCUMULATE Simulate one PL dwell without retaining ordinary waveforms.
% X = I+jQ uses cosine and negative-sine references.
if nargin < 4, keepDebug = false; end

probe = generate_dds(cfg, frequency, 0);
fa = probe.frequency_actual;
H = circuit.response(fa);
N = max(32, round(cfg.sweep.cycles * cfg.learn.fs / fa));
useChunks = keepDebug || cfg.sweep.ordinary_engine == "chunked";

if useChunks
    [sumVals, debug] = accumulate_chunks(cfg, H, frequency, N, keepDebug);
else
    [sumVals, debug] = accumulate_statistics(cfg, H, frequency, N);
end

scale = 2 / N;
iq.Ix = sumVals(1) * scale;
iq.Qx = sumVals(2) * scale;
iq.Iy = sumVals(3) * scale;
iq.Qy = sumVals(4) * scale;
iq.sample_count = N;
iq.frequency_actual = fa;
end

function [sums, debug] = accumulate_chunks(cfg, H, frequency, N, keepDebug)
sums = zeros(1,4);
debug = struct();
stored = 0;
traceEvery = max(1, floor(N / cfg.sweep.convergence_windows));
nextTrace = traceEvery;
traceN = zeros(cfg.sweep.convergence_windows + 1, 1);
traceS = zeros(cfg.sweep.convergence_windows + 1, 4);
traceCount = 0;

for first = 0:cfg.sweep.chunk_samples:N-1
    idx = (first:min(first + cfg.sweep.chunk_samples - 1, N-1)).';
    dds = generate_dds(cfg, frequency, idx);
    xAnalog = dac_model(cfg, dds.output, true);
    yAnalog = abs(H) * cfg.dac.gain * cfg.sweep.amplitude * ...
        cos(2*pi*dds.frequency_actual*idx/cfg.learn.fs + angle(H));
    xAdc = adc_model(cfg, xAnalog, true);
    yAdc = adc_model(cfg, yAnalog, true);
    products = [xAdc.*dds.cosine, -xAdc.*dds.sine, ...
                yAdc.*dds.cosine, -yAdc.*dds.sine];
    sums = sums + sum(products, 1);

    while first + numel(idx) >= nextTrace && traceCount < numel(traceN)
        localN = nextTrace - first;
        partial = sums - sum(products(localN+1:end,:), 1);
        traceCount = traceCount + 1;
        traceN(traceCount) = nextTrace;
        traceS(traceCount,:) = partial;
        nextTrace = nextTrace + traceEvery;
    end

    if keepDebug && stored < cfg.sweep.debug_max_samples
        take = min(numel(idx), cfg.sweep.debug_max_samples - stored);
        rr = stored + (1:take);
        debug.time(rr,1) = idx(1:take) / cfg.learn.fs;
        debug.dds(rr,1) = dds.output(1:take);
        debug.i_ref(rr,1) = dds.cosine(1:take);
        debug.q_ref(rr,1) = -dds.sine(1:take);
        debug.x_dac(rr,1) = xAnalog(1:take);
        debug.x_adc(rr,1) = xAdc(1:take);
        debug.y_adc(rr,1) = yAdc(1:take);
        debug.i_product_x(rr,1) = products(1:take,1);
        debug.q_product_x(rr,1) = products(1:take,2);
        debug.i_product_y(rr,1) = products(1:take,3);
        debug.q_product_y(rr,1) = products(1:take,4);
        stored = stored + take;
    end
end

if keepDebug
    valid = traceN > 0;
    debug.accumulation_samples = traceN(valid);
    debug.accumulation = traceS(valid,:);
    debug.total_samples = N;
    debug.waveform_truncated = N > cfg.sweep.debug_max_samples;
end
end

function [sums, debug] = accumulate_statistics(cfg, H, frequency, N)
% Closed-form coherent sums plus the accumulated converter-noise variance.
dds = generate_dds(cfg, frequency, 0);
w = 2*pi*dds.frequency_actual/cfg.learn.fs;
[cc, ss, cs] = trig_sums(w, N);
Ax = cfg.dac.gain * cfg.sweep.amplitude;
Ay = Ax * abs(H);
phi = angle(H);
sums = [Ax*cc, -Ax*cs, ...
        Ay*(cos(phi)*cc - sin(phi)*cs), ...
        Ay*(-cos(phi)*cs + sin(phi)*ss)];

% Treat DAC/ADC quantization and noise as white at the accumulator boundary.
qRms = 1 / (sqrt(12) * (2^(cfg.adc.bits-1)-1));
sigma = hypot(cfg.adc.noise_rms, qRms);
refEnergy = [cc ss cc ss];
sums = sums + sigma * sqrt(refEnergy) .* randn(1,4);
debug = struct();
end

function [cc, ss, cs] = trig_sums(w, N)
% Sum cos^2, sin^2 and cos*sin without constructing an N-vector.
if abs(sin(w)) < 1e-14
    c2 = N;
    s2 = 0;
else
    z = (1 - exp(1j*2*w*N)) / (1 - exp(1j*2*w));
    c2 = real(z);
    s2 = imag(z);
end
cc = 0.5 * (N + c2);
ss = 0.5 * (N - c2);
cs = 0.5 * s2;
end
