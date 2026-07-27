function snapshot = pack_iq_data(cfg, f, actualF, sampleCount, iqFloat, debug)
%PACK_IQ_DATA Model the 32 KiB measurement BRAM IQ_INT16_X4 snapshot.
peak = cfg.adc.iq_payload_peak;
q = int16(min(max(round(iqFloat * peak), -32768), 32767));
n = size(q,1);
payload = zeros(2*n, 1, 'uint32');
for k = 1:n
    payload(2*k-1) = pack_pair(q(k,1), q(k,2));
    payload(2*k)   = pack_pair(q(k,3), q(k,4));
end
assert(numel(payload) <= 8176, 'Measurement BRAM capacity exceeded.');

snapshot.header = struct('magic', uint32(hex2dec('4D454153')), ...
    'version', uint32(hex2dec('00010000')), 'generation', uint32(1), ...
    'status', uint32(1), 'word_count', uint32(numel(payload)), ...
    'format', uint32(1), 'error_code', uint32(0));
snapshot.payload = payload;
snapshot.frequencies = f;
snapshot.actual_frequencies = actualF;
snapshot.sample_count = sampleCount;
snapshot.iq_scale = peak;
snapshot.debug = debug;
end

function word = pack_pair(a, b)
ua = typecast(int16(a), 'uint16');
ub = typecast(int16(b), 'uint16');
word = bitor(bitshift(uint32(ua), 16), uint32(ub));
end
