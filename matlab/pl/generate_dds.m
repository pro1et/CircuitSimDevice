function dds = generate_dds(cfg, frequency, sampleIndex)
%GENERATE_DDS Quantized phase-increment DDS and coherent IQ references.
modulus = 2^cfg.sweep.dds_phase_bits;
phase_increment = round(frequency / cfg.learn.fs * modulus);
actual_frequency = phase_increment / modulus * cfg.learn.fs;
phase = 2*pi * mod(double(sampleIndex(:)) * phase_increment, modulus) / modulus;

dds.frequency_requested = frequency;
dds.frequency_actual = actual_frequency;
dds.phase_increment = uint32(phase_increment);
dds.cosine = cos(phase);
dds.sine = sin(phase);
dds.output = cfg.sweep.amplitude * dds.cosine;
end
