function response = calculate_response(~, snapshot)
%CALCULATE_RESPONSE ARM-equivalent stable snapshot read and H=Y/X.
h = snapshot.header;
assert(h.magic == uint32(hex2dec('4D454153')), 'Bad measurement MAGIC.');
assert(h.version == uint32(hex2dec('00010000')), 'Unsupported protocol version.');
assert(bitand(h.status, uint32(3)) == 1, 'Measurement snapshot is not DONE.');
assert(h.format == 1 && mod(double(h.word_count),2) == 0, ...
    'Unsupported or malformed measurement payload.');

n = double(h.word_count) / 2;
q = zeros(n,4,'int16');
for k = 1:n
    [q(k,1), q(k,2)] = unpack_pair(snapshot.payload(2*k-1));
    [q(k,3), q(k,4)] = unpack_pair(snapshot.payload(2*k));
end
v = double(q) / snapshot.iq_scale;
X = complex(v(:,1), v(:,2));
Y = complex(v(:,3), v(:,4));
threshold = max(abs(X)) * 1e-5;
valid = abs(X) > threshold;
H = nan(size(X));
H(valid) = Y(valid) ./ X(valid);

response.frequencies = snapshot.frequencies;
response.actual_frequencies = snapshot.actual_frequencies;
response.X = X;
response.Y = Y;
response.H = H;
response.valid = valid;
response.iq_int16 = q;
response.generation = h.generation;
end

function [a,b] = unpack_pair(word)
ua = uint16(bitshift(word, -16));
ub = uint16(bitand(word, uint32(65535)));
a = typecast(ua, 'int16');
b = typecast(ub, 'int16');
end
