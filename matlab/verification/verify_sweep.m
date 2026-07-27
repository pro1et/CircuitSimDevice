function metrics = verify_sweep(~, circuit, response)
%VERIFY_SWEEP Compare the batch IQ response with the analog DUT response.
truth = circuit.response(response.actual_frequencies);
truth = truth(:);
valid = response.valid & abs(truth) > 1e-12;
ratio = response.H(valid) ./ truth(valid);
magError = 20*log10(max(abs(ratio), realmin));
phaseError = angle(ratio) * 180/pi;

metrics.magnitude_rms_db = sqrt(mean(magError.^2));
metrics.magnitude_max_db = max(abs(magError));
metrics.phase_rms_deg = sqrt(mean(phaseError.^2));
metrics.phase_max_deg = max(abs(phaseError));
metrics.valid_points = nnz(valid);
metrics.theoretical_response = truth;
end
