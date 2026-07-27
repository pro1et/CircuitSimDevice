function circuit = create_circuit(~)
%CREATE_CIRCUIT Example stable analog DUT with two poles and one zero.
% The transfer is deliberately non-trivial while remaining easy to replace.
gain = 0.82;
fz = 12e3;
fp1 = 3.2e3;
fp2 = 34e3;
s = tf('s');
sys = gain * (1 + s/(2*pi*fz)) / ...
    ((1 + s/(2*pi*fp1)) * (1 + s/(2*pi*fp2)));

circuit.name = 'two-pole/one-zero low-pass example';
circuit.sys = minreal(sys);
circuit.parameters = struct('gain', gain, 'zero_hz', fz, ...
    'pole_hz', [fp1 fp2]);
circuit.response = @(f) squeeze(freqresp(circuit.sys, 2*pi*f));
end
