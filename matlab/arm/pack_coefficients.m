function snapshot = pack_coefficients(cfg, solution)
%PACK_COEFFICIENTS Model ARM publication of 129 Q1.31 words to coefficient BRAM.
scaled = round(solution.taps(:) * 2^31);
clipped = min(max(scaled, -2^31), 2^31-1);
raw = int32(clipped);
payload = typecast(raw, 'uint32');
assert(numel(payload) == cfg.fir.tap_count && numel(payload) <= 1008, ...
    'Coefficient payload size is invalid.');

snapshot.header = struct('magic', uint32(hex2dec('434F4546')), ...
    'version', uint32(hex2dec('00010000')), 'generation', uint32(1), ...
    'status', uint32(1), 'tap_count', uint32(numel(payload)), ...
    'format', uint32(1), 'scale', uint32(31));
snapshot.payload = payload(:);
snapshot.quantized_taps = double(raw(:)).' / 2^31;
snapshot.saturated_count = nnz(scaled ~= clipped);
end
