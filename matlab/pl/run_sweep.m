function snapshot = run_sweep(cfg, circuit)
%RUN_SWEEP PL-equivalent complete sweep, cache, then atomic publication.
f = cfg.sweep.frequencies;
nPoints = numel(f);
raw = zeros(nPoints, 4);
sampleCount = zeros(nPoints, 1);
actualF = zeros(nPoints, 1);
debugIndex = unique(arrayfun(@(x) find(abs(f-x)==min(abs(f-x)),1), ...
    cfg.sweep.debug_frequencies));
debugCell = cell(numel(debugIndex), 1);
debugCount = 0;
fprintf('PL sweep started (STATUS=BUSY)...\n');
for k = 1:nPoints
    keep = any(k == debugIndex);
    [iq, dbg] = iq_accumulate(cfg, circuit, f(k), keep);
    raw(k,:) = [iq.Ix iq.Qx iq.Iy iq.Qy];
    sampleCount(k) = iq.sample_count;
    actualF(k) = iq.frequency_actual;
    if keep
        dbg.frequency_requested = f(k);
        dbg.frequency_actual = iq.frequency_actual;
        debugCount = debugCount + 1;
        debugCell{debugCount} = dbg;
    end
end

debug = debugCell;
snapshot = pack_iq_data(cfg, f, actualF, sampleCount, raw, debug);
fprintf('PL published generation %d (STATUS=DONE, %d payload words).\n', ...
    snapshot.header.generation, snapshot.header.word_count);
end
