function plot_debug_signals(cfg, circuit, response, solution, firMetrics, debug)
%PLOT_DEBUG_SIGNALS Save stage-by-stage diagnostic figures.
vis = cfg.output.figure_visible;

for k = 1:numel(debug)
    if iscell(debug), d = debug{k}; else, d = debug(k); end
    fig = figure('Visible', vis, 'Color', 'w', 'Position', [100 100 1150 800]);
    tiledlayout(3,2, 'TileSpacing','compact');
    showN = min(numel(d.time), max(2000, round(4*cfg.learn.fs/d.frequency_actual)));
    nexttile; plot(d.time(1:showN)*1e3, d.dds(1:showN)); grid on;
    title('DDS output'); xlabel('Time (ms)'); ylabel('Normalized V');
    nexttile; plot(d.time(1:showN)*1e3, d.x_dac(1:showN)); hold on;
    plot(d.time(1:showN)*1e3, d.y_adc(1:showN)); grid on;
    title('DUT input/output'); legend('DAC/input','ADC/output'); xlabel('Time (ms)');
    nexttile; plot(d.time(1:showN)*1e3, d.i_product_x(1:showN)); hold on;
    plot(d.time(1:showN)*1e3, d.q_product_x(1:showN)); grid on;
    title('Input IQ products'); legend('x cos','x (-sin)'); xlabel('Time (ms)');
    nexttile; plot(d.time(1:showN)*1e3, d.i_product_y(1:showN)); hold on;
    plot(d.time(1:showN)*1e3, d.q_product_y(1:showN)); grid on;
    title('Output IQ products'); legend('y cos','y (-sin)'); xlabel('Time (ms)');
    nexttile([1 2]);
    n = d.accumulation_samples;
    z = 2*d.accumulation./n;
    plot(n, z, 'LineWidth', 1.1); grid on;
    title(sprintf('IQ accumulator convergence at %.1f Hz',d.frequency_actual));
    xlabel('Accumulated samples'); ylabel('Normalized IQ');
    legend('I_x','Q_x','I_y','Q_y','Location','best');
    exportgraphics(fig, fullfile(cfg.paths.results, ...
        sprintf('debug_%06d_Hz.png', round(d.frequency_requested))));
    close(fig);
end

truth = circuit.response(response.actual_frequencies); truth = truth(:);
A = exp(-1j*2*pi/cfg.fir.fs*(response.actual_frequencies*(0:cfg.fir.order)));
Hfir = A*solution.taps(:);
fig = figure('Visible',vis,'Color','w','Position',[100 100 1100 760]);
tiledlayout(2,1,'TileSpacing','compact');
nexttile; semilogx(response.frequencies,20*log10(abs(truth)),'k--','LineWidth',1.3); hold on;
semilogx(response.frequencies,20*log10(abs(response.H)),'b');
semilogx(response.frequencies,20*log10(abs(Hfir)),'r'); grid on;
ylabel('Magnitude (dB)'); legend('DUT theory','IQ measurement','129-tap FIR');
title('Complete batch frequency response');
nexttile; semilogx(response.frequencies,unwrap(angle(truth))*180/pi,'k--','LineWidth',1.3); hold on;
semilogx(response.frequencies,unwrap(angle(response.H))*180/pi,'b');
semilogx(response.frequencies,unwrap(angle(Hfir))*180/pi,'r'); grid on;
xlabel('Frequency (Hz)'); ylabel('Phase (deg)');
exportgraphics(fig,fullfile(cfg.paths.results,'frequency_response.png')); close(fig);

fig = figure('Visible',vis,'Color','w','Position',[100 100 1100 760]);
tiledlayout(2,1,'TileSpacing','compact');
nexttile; stem(0:cfg.fir.order,solution.taps,'.'); grid on;
xlabel('Tap index'); ylabel('Coefficient'); title('Learned real non-symmetric FIR coefficients');
nexttile; plot(firMetrics.time*1e3,firMetrics.dut_output,'k','LineWidth',1.0); hold on;
plot(firMetrics.time*1e3,firMetrics.fir_output,'r--'); grid on;
xlabel('Time (ms)'); ylabel('Output'); legend('DUT','learned FIR'); title('Time-domain reproduction');
exportgraphics(fig,fullfile(cfg.paths.results,'fir_and_time_response.png')); close(fig);
end
