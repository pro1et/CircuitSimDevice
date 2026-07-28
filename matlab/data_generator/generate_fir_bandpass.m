function generate_fir_bandpass
%GENERATE_FIR_BANDPASS 生成任务 D 使用的 129 阶带通 FIR 系数镜像。
%
% 设计约束：
%   - FIR 输入采样率：300 kHz
%   - 抽头数：129（滤波器阶数为 128）
%   - -3 dB 通带边界：10 kHz、25 kHz
%   - 系数格式：Q1.31
%
% 输出文件遵循《PS端共享BRAM访问与STATUS通知协议》中的 4 KiB
% 系数 BRAM 镜像格式：前 16 个字为头部，之后为 129 个系数，其余补零。

    sample_rate_hz = 300000;
    tap_count = 129;
    filter_order = tap_count - 1;
    passband_edges_hz = [10000, 25000];
    passband_center_hz = mean(passband_edges_hz);
    target_edge_db = -3.0;
    kaiser_beta = 6.0;

    script_dir = fileparts(mfilename('fullpath'));
    repo_root = fileparts(script_dir);
    data_dir = fullfile(script_dir, 'data');
    fpga_doc_dir = fullfile(repo_root, 'fpga', 'doc');

    if ~exist(data_dir, 'dir')
        mkdir(data_dir);
    end
    if ~exist(fpga_doc_dir, 'dir')
        error('找不到 FPGA 文档目录：%s', fpga_doc_dir);
    end

    % fir1 的 Wn 并不直接等于有限阶滤波器的 -3 dB 点，因此优化两个
    % 设计边界，并且在目标函数中使用量化后的 Q1.31 系数校准边界响应。
    initial_edges_hz = [8500, 27000];
    objective = @(design_edges_hz) edge_error( ...
        design_edges_hz, filter_order, tap_count, sample_rate_hz, ...
        passband_edges_hz, passband_center_hz, target_edge_db, kaiser_beta);

    options = optimset( ...
        'Display', 'off', ...
        'TolX', 1e-7, ...
        'TolFun', 1e-14, ...
        'MaxFunEvals', 2000, ...
        'MaxIter', 1000);
    design_edges_hz = fminsearch(objective, initial_edges_hz, options);

    coefficients = make_quantized_filter( ...
        design_edges_hz, filter_order, tap_count, sample_rate_hz, ...
        passband_center_hz, kaiser_beta);
    coefficient_q31 = quantize_q31(coefficients);
    coefficients = double(coefficient_q31) / 2^31;

    edge_response = freqz(coefficients, 1, passband_edges_hz, sample_rate_hz);
    edge_db = 20 * log10(abs(edge_response));
    [low_crossing_hz, high_crossing_hz, passband_ripple_db, ...
        low_stopband_db, high_stopband_db] = measure_response( ...
        coefficients, sample_rate_hz, target_edge_db, passband_edges_hz);

    if any(abs(edge_db - target_edge_db) > 0.01)
        error('量化后目标边界未达到 -3 dB：%.6f dB、%.6f dB', ...
            edge_db(1), edge_db(2));
    end
    if abs(low_crossing_hz - passband_edges_hz(1)) > 20 || ...
            abs(high_crossing_hz - passband_edges_hz(2)) > 20
        error('实测 -3 dB 交点超出 20 Hz 容差。');
    end

    bram_words = make_protocol_image(coefficient_q31, tap_count);
    output_name = 'fir_bandpass_10k_25k.coe';
    data_coe_path = fullfile(data_dir, output_name);
    doc_coe_path = fullfile(fpga_doc_dir, output_name);

    write_coe(data_coe_path, bram_words);
    [copy_ok, copy_message] = copyfile(data_coe_path, doc_coe_path, 'f');
    if ~copy_ok
        error('无法复制 COE 到 fpga/doc：%s', copy_message);
    end

    fprintf('FIR 带通系数生成完成。\n');
    fprintf('  采样率 / 抽头数       : %.0f Hz / %d\n', sample_rate_hz, tap_count);
    fprintf('  fir1 校准设计边界     : %.6f Hz, %.6f Hz\n', ...
        design_edges_hz(1), design_edges_hz(2));
    fprintf('  10 kHz / 25 kHz 幅度  : %.6f dB, %.6f dB\n', ...
        edge_db(1), edge_db(2));
    fprintf('  实测 -3 dB 交点       : %.3f Hz, %.3f Hz\n', ...
        low_crossing_hz, high_crossing_hz);
    fprintf('  12--23 kHz 峰峰纹波   : %.6f dB\n', passband_ripple_db);
    fprintf('  <=5 kHz 最大幅度      : %.3f dB\n', low_stopband_db);
    fprintf('  >=35 kHz 最大幅度     : %.3f dB\n', high_stopband_db);
    fprintf('  BRAM 镜像字数         : %d x 32 bit\n', numel(bram_words));
    fprintf('  主文件                 : %s\n', data_coe_path);
    fprintf('  文档副本               : %s\n', doc_coe_path);
end

function cost = edge_error(design_edges_hz, filter_order, tap_count, ...
        sample_rate_hz, target_edges_hz, center_hz, target_db, kaiser_beta)
    % 防止 fminsearch 进入无效或顺序颠倒的设计区域。
    if design_edges_hz(1) <= 1000 || ...
            design_edges_hz(1) >= target_edges_hz(1) || ...
            design_edges_hz(2) <= target_edges_hz(2) || ...
            design_edges_hz(2) >= sample_rate_hz / 2 - 1000 || ...
            design_edges_hz(1) >= design_edges_hz(2)
        cost = 1e9 + sum(design_edges_hz .^ 2);
        return;
    end

    coefficients = make_quantized_filter( ...
        design_edges_hz, filter_order, tap_count, sample_rate_hz, ...
        center_hz, kaiser_beta);
    response = freqz(coefficients, 1, target_edges_hz, sample_rate_hz);
    response_db = 20 * log10(max(abs(response), realmin));
    cost = sum((response_db - target_db) .^ 2);
end

function coefficients = make_quantized_filter(design_edges_hz, ...
        filter_order, tap_count, sample_rate_hz, center_hz, kaiser_beta)
    coefficients = fir1( ...
        filter_order, ...
        design_edges_hz / (sample_rate_hz / 2), ...
        'bandpass', ...
        kaiser(tap_count, kaiser_beta), ...
        'scale');

    % 以通带中心作为 0 dB 参考，然后量化；这与后续测量的参考一致。
    % freqz 对标量第三参数会按 FFT 点数解释，因此使用双元素频率向量
    % 强制进入“指定 Hz 频点”调用形式。
    center_response = freqz( ...
        coefficients, 1, [center_hz, center_hz], sample_rate_hz);
    coefficients = coefficients / abs(center_response(1));
    coefficients = double(quantize_q31(coefficients)) / 2^31;
end

function values_q31 = quantize_q31(coefficients)
    scaled = round(coefficients * 2^31);
    scaled = min(max(scaled, -2^31), 2^31 - 1);
    values_q31 = int32(scaled);
end

function words = make_protocol_image(coefficient_q31, tap_count)
    word_count = 1024;
    header_words = 16;
    words = zeros(word_count, 1, 'uint32');

    words(1) = uint32(hex2dec('434F4546')); % MAGIC：ASCII "COEF"
    words(2) = uint32(hex2dec('00010000')); % VERSION：v1.0
    words(3) = uint32(1);                   % GENERATION：首版镜像
    words(4) = uint32(1);                   % STATUS：VALID
    words(5) = uint32(tap_count);           % TAP_COUNT：129
    words(6) = uint32(1);                   % FORMAT：Q1.31
    words(7) = uint32(31);                  % SCALE：31
    % words(8:16) 为协议保留字段，保持为 0。

    % typecast 保留负数的二进制补码位型。
    coefficient_words = typecast(coefficient_q31(:), 'uint32');
    words(header_words + 1:header_words + tap_count) = coefficient_words;
end

function write_coe(path, words)
    file_id = fopen(path, 'wt');
    if file_id < 0
        error('无法创建 COE 文件：%s', path);
    end
    cleanup = onCleanup(@() fclose(file_id));

    fprintf(file_id, 'memory_initialization_radix=16;\n');
    fprintf(file_id, 'memory_initialization_vector=\n');
    for index = 1:numel(words)
        if index < numel(words)
            fprintf(file_id, '%08X,\n', words(index));
        else
            fprintf(file_id, '%08X;\n', words(index));
        end
    end

    clear cleanup;
end

function [low_crossing_hz, high_crossing_hz, ripple_db, ...
        low_stopband_db, high_stopband_db] = measure_response( ...
        coefficients, sample_rate_hz, target_db, target_edges_hz)
    fft_points = 2^19;
    [response, frequencies_hz] = freqz( ...
        coefficients, 1, fft_points, sample_rate_hz);
    response_db = 20 * log10(max(abs(response), realmin));

    low_crossing_hz = nearest_crossing( ...
        frequencies_hz, response_db, target_db, target_edges_hz(1), true);
    high_crossing_hz = nearest_crossing( ...
        frequencies_hz, response_db, target_db, target_edges_hz(2), false);

    ripple_region = frequencies_hz >= 12000 & frequencies_hz <= 23000;
    ripple_db = max(response_db(ripple_region)) - min(response_db(ripple_region));
    low_stopband_db = max(response_db(frequencies_hz <= 5000));
    high_stopband_db = max(response_db(frequencies_hz >= 35000));
end

function crossing_hz = nearest_crossing(frequencies_hz, response_db, ...
        target_db, expected_hz, rising)
    if rising
        indices = find(response_db(1:end-1) <= target_db & ...
            response_db(2:end) > target_db);
    else
        indices = find(response_db(1:end-1) >= target_db & ...
            response_db(2:end) < target_db);
    end
    if isempty(indices)
        error('未找到目标 %.3f dB 交点。', target_db);
    end

    interpolated = zeros(size(indices));
    for item = 1:numel(indices)
        index = indices(item);
        fraction = (target_db - response_db(index)) / ...
            (response_db(index + 1) - response_db(index));
        interpolated(item) = frequencies_hz(index) + fraction * ...
            (frequencies_hz(index + 1) - frequencies_hz(index));
    end
    [~, nearest] = min(abs(interpolated - expected_hz));
    crossing_hz = interpolated(nearest);
end
