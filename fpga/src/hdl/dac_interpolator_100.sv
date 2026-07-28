`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：dac_interpolator_100
//
// 主要功能：
//   将低速signed采样流进行100倍多相FIR插值，为每个输入样本连续产生100个高速
//   输出样本。固定滤波器为400抽头、100相、每相4抽头，消除显式插零造成的无效
//   乘法，供300 kS/s FIR结果连接30 MS/s DAC使用。
//
// 使用方法：
//   1. clk/rst连接30 MHz处理时钟和本域高有效同步复位。
//   2. 上游仅在in_ready为高时用单拍in_valid提交一个signed样本。
//   3. out_valid为高的每个周期接收一个插值结果并送入fir_data_adapter。
//
// 连接说明：
//   clk               <- clock_tree的30 MHz处理时钟
//   rst               <- clock_tree的30 MHz域高有效复位
//   data_in/in_valid   <- fir_filter的out_data/out_valid
//   in_ready           -> 顶层输入间隔检查；当前FIR固定每100拍产生一个结果
//   data_out/out_valid -> fir_data_adapter的fir_out_data/fir_out_valid
//   overflow           -> 顶层粘滞错误状态或ILA
//
// 时钟与复位：
//   全部逻辑工作在clk域，不生成派生时钟。rst高有效同步复位，复位清空4个输入
//   历史样本、相位、输出valid及overflow，解除复位后等待第一个输入样本。
//
// 输入格式：
//   data_in为DATA_W位signed二进制补码。任务D使用10位，范围-512..511；输入
//   等效采样率为clk/100，且相邻有效脉冲不得短于100个clk周期。
//
// 输出格式：
//   data_out与输入同为DATA_W位signed补码。系数为18位signed Q2.16，乘积累加后
//   加2^15并算术右移16位，最后饱和到DATA_W位，不发生回绕。
//
// 握手时序：
//   空闲或正在输出phase=99时in_ready为高。首次接收后下一拍输出phase=0；每个
//   输入严格产生phase=0..99共100拍out_valid。phase=99同拍可接收下一输入，因而
//   稳态输出无空拍。其他相位到来的单拍in_valid被拒绝并置overflow。
//
// 参数说明：
//   DATA_W为输入输出位宽，范围2..16；ACC_W为内部累加位宽，至少DATA_W+20。
//   插值倍数、相数、抽头数及系数固定，不通过参数改变。
//
// 滤波器指标：
//   系数由400抽头Kaiser窗低通量化得到，输入/输出采样率为300 kS/s/30 MS/s；
//   0..25 kHz内最大幅度下降约0.18 dB，275 kHz以上第一镜像相对通带抑制约
//   63 dB。总系数增益约100，用于补偿插零造成的1/100幅度。
//
// 错误行为：
//   in_ready为低时出现的单拍in_valid不会改变历史数据，并使overflow保持为高，
//   直到复位。模块不提供输出反压，下游必须能够连续接收100个高速样本。
//
// 使用限制：
//   当前滤波器面向最高25 kHz有效信号。改变低速采样率、插值倍数或有效带宽时
//   必须重新设计和量化系数，并重新检查频响、DSP资源、定点溢出和时序。
// ============================================================================

module dac_interpolator_100 #(
    parameter int unsigned DATA_W = 10, // 输入输出signed位宽，合法范围2..16
    parameter int unsigned ACC_W  = 30  // 乘加累加器位宽，必须大于等于DATA_W+20
) (
    input  wire  logic                     clk,       // 30 MHz模块工作时钟
    input  wire  logic                     rst,       // clk域高有效同步复位

    input  wire  logic signed [DATA_W-1:0] data_in,   // 低速signed补码输入样本
    input  wire  logic                     in_valid,  // 单拍输入有效，仅in_ready高时提交
    output wire  logic                     in_ready,  // 可接收新输入，空闲或phase=99时为高

    output       logic signed [DATA_W-1:0] data_out,  // 饱和后的高速signed补码输出
    output       logic                     out_valid, // 输出有效，连续保持100个clk周期
    output       logic                     overflow   // 过早输入粘滞错误，高有效
);

    localparam int unsigned INTERP_FACTOR = 100;
    localparam int unsigned TAPS_PER_PHASE = 4;
    localparam int unsigned COEF_W = 18;
    localparam int unsigned COEF_FRAC = 16;
    localparam int unsigned PRODUCT_W = DATA_W + COEF_W;
    localparam int unsigned PHASE_W = $clog2(INTERP_FACTOR);

    logic active;
    logic [PHASE_W-1:0] phase;
    logic signed [DATA_W-1:0] history [0:TAPS_PER_PHASE-1];
    // 异步四端口系数读取强制使用分布式ROM，避免BRAM异步地址控制DRC问题。
    (* rom_style = "distributed" *) logic signed [COEF_W-1:0] coeff_rom [0:399];
    logic signed [COEF_W-1:0] phase_coef [0:TAPS_PER_PHASE-1];
    logic signed [PRODUCT_W-1:0] phase_product [0:TAPS_PER_PHASE-1];
    logic signed [ACC_W-1:0] phase_sum;
    logic signed [ACC_W-1:0] rounded_sum;
    integer lane;
    integer reset_index;
    integer coef_index;

    initial begin
        assert ((DATA_W >= 2) && (DATA_W <= 16))
            else $fatal(1, "DATA_W必须在2到16之间");
        assert (ACC_W >= (DATA_W + COEF_W + $clog2(TAPS_PER_PHASE)))
            else $fatal(1, "ACC_W不足，至少需要DATA_W+20位");
    end

    // 400抽头线性相位对称系数只保存前200项，后半部分镜像读取。
    function automatic logic signed [COEF_W-1:0] coefficient_half(
        input logic [7:0] index
    );
        begin
            case (index)
            8'd0: coefficient_half = -18'sd188;
            8'd1: coefficient_half = -18'sd207;
            8'd2: coefficient_half = -18'sd228;
            8'd3: coefficient_half = -18'sd249;
            8'd4: coefficient_half = -18'sd271;
            8'd5: coefficient_half = -18'sd295;
            8'd6: coefficient_half = -18'sd319;
            8'd7: coefficient_half = -18'sd345;
            8'd8: coefficient_half = -18'sd372;
            8'd9: coefficient_half = -18'sd399;
            8'd10: coefficient_half = -18'sd428;
            8'd11: coefficient_half = -18'sd458;
            8'd12: coefficient_half = -18'sd489;
            8'd13: coefficient_half = -18'sd520;
            8'd14: coefficient_half = -18'sd553;
            8'd15: coefficient_half = -18'sd587;
            8'd16: coefficient_half = -18'sd622;
            8'd17: coefficient_half = -18'sd657;
            8'd18: coefficient_half = -18'sd693;
            8'd19: coefficient_half = -18'sd730;
            8'd20: coefficient_half = -18'sd768;
            8'd21: coefficient_half = -18'sd807;
            8'd22: coefficient_half = -18'sd846;
            8'd23: coefficient_half = -18'sd886;
            8'd24: coefficient_half = -18'sd926;
            8'd25: coefficient_half = -18'sd967;
            8'd26: coefficient_half = -18'sd1008;
            8'd27: coefficient_half = -18'sd1049;
            8'd28: coefficient_half = -18'sd1090;
            8'd29: coefficient_half = -18'sd1132;
            8'd30: coefficient_half = -18'sd1174;
            8'd31: coefficient_half = -18'sd1215;
            8'd32: coefficient_half = -18'sd1256;
            8'd33: coefficient_half = -18'sd1297;
            8'd34: coefficient_half = -18'sd1338;
            8'd35: coefficient_half = -18'sd1378;
            8'd36: coefficient_half = -18'sd1418;
            8'd37: coefficient_half = -18'sd1456;
            8'd38: coefficient_half = -18'sd1494;
            8'd39: coefficient_half = -18'sd1530;
            8'd40: coefficient_half = -18'sd1566;
            8'd41: coefficient_half = -18'sd1600;
            8'd42: coefficient_half = -18'sd1633;
            8'd43: coefficient_half = -18'sd1663;
            8'd44: coefficient_half = -18'sd1692;
            8'd45: coefficient_half = -18'sd1720;
            8'd46: coefficient_half = -18'sd1745;
            8'd47: coefficient_half = -18'sd1767;
            8'd48: coefficient_half = -18'sd1787;
            8'd49: coefficient_half = -18'sd1805;
            8'd50: coefficient_half = -18'sd1819;
            8'd51: coefficient_half = -18'sd1831;
            8'd52: coefficient_half = -18'sd1839;
            8'd53: coefficient_half = -18'sd1844;
            8'd54: coefficient_half = -18'sd1845;
            8'd55: coefficient_half = -18'sd1842;
            8'd56: coefficient_half = -18'sd1835;
            8'd57: coefficient_half = -18'sd1824;
            8'd58: coefficient_half = -18'sd1809;
            8'd59: coefficient_half = -18'sd1789;
            8'd60: coefficient_half = -18'sd1764;
            8'd61: coefficient_half = -18'sd1734;
            8'd62: coefficient_half = -18'sd1698;
            8'd63: coefficient_half = -18'sd1657;
            8'd64: coefficient_half = -18'sd1611;
            8'd65: coefficient_half = -18'sd1558;
            8'd66: coefficient_half = -18'sd1499;
            8'd67: coefficient_half = -18'sd1434;
            8'd68: coefficient_half = -18'sd1363;
            8'd69: coefficient_half = -18'sd1284;
            8'd70: coefficient_half = -18'sd1199;
            8'd71: coefficient_half = -18'sd1106;
            8'd72: coefficient_half = -18'sd1006;
            8'd73: coefficient_half = -18'sd899;
            8'd74: coefficient_half = -18'sd783;
            8'd75: coefficient_half = -18'sd660;
            8'd76: coefficient_half = -18'sd528;
            8'd77: coefficient_half = -18'sd388;
            8'd78: coefficient_half = -18'sd239;
            8'd79: coefficient_half = -18'sd82;
            8'd80: coefficient_half = 18'sd84;
            8'd81: coefficient_half = 18'sd260;
            8'd82: coefficient_half = 18'sd444;
            8'd83: coefficient_half = 18'sd639;
            8'd84: coefficient_half = 18'sd842;
            8'd85: coefficient_half = 18'sd1056;
            8'd86: coefficient_half = 18'sd1279;
            8'd87: coefficient_half = 18'sd1512;
            8'd88: coefficient_half = 18'sd1756;
            8'd89: coefficient_half = 18'sd2010;
            8'd90: coefficient_half = 18'sd2274;
            8'd91: coefficient_half = 18'sd2548;
            8'd92: coefficient_half = 18'sd2833;
            8'd93: coefficient_half = 18'sd3129;
            8'd94: coefficient_half = 18'sd3436;
            8'd95: coefficient_half = 18'sd3753;
            8'd96: coefficient_half = 18'sd4081;
            8'd97: coefficient_half = 18'sd4420;
            8'd98: coefficient_half = 18'sd4770;
            8'd99: coefficient_half = 18'sd5131;
            8'd100: coefficient_half = 18'sd5503;
            8'd101: coefficient_half = 18'sd5886;
            8'd102: coefficient_half = 18'sd6280;
            8'd103: coefficient_half = 18'sd6685;
            8'd104: coefficient_half = 18'sd7101;
            8'd105: coefficient_half = 18'sd7527;
            8'd106: coefficient_half = 18'sd7965;
            8'd107: coefficient_half = 18'sd8413;
            8'd108: coefficient_half = 18'sd8872;
            8'd109: coefficient_half = 18'sd9341;
            8'd110: coefficient_half = 18'sd9821;
            8'd111: coefficient_half = 18'sd10312;
            8'd112: coefficient_half = 18'sd10812;
            8'd113: coefficient_half = 18'sd11323;
            8'd114: coefficient_half = 18'sd11844;
            8'd115: coefficient_half = 18'sd12374;
            8'd116: coefficient_half = 18'sd12914;
            8'd117: coefficient_half = 18'sd13463;
            8'd118: coefficient_half = 18'sd14022;
            8'd119: coefficient_half = 18'sd14590;
            8'd120: coefficient_half = 18'sd15166;
            8'd121: coefficient_half = 18'sd15751;
            8'd122: coefficient_half = 18'sd16344;
            8'd123: coefficient_half = 18'sd16946;
            8'd124: coefficient_half = 18'sd17554;
            8'd125: coefficient_half = 18'sd18171;
            8'd126: coefficient_half = 18'sd18794;
            8'd127: coefficient_half = 18'sd19425;
            8'd128: coefficient_half = 18'sd20061;
            8'd129: coefficient_half = 18'sd20704;
            8'd130: coefficient_half = 18'sd21353;
            8'd131: coefficient_half = 18'sd22007;
            8'd132: coefficient_half = 18'sd22667;
            8'd133: coefficient_half = 18'sd23331;
            8'd134: coefficient_half = 18'sd23999;
            8'd135: coefficient_half = 18'sd24672;
            8'd136: coefficient_half = 18'sd25347;
            8'd137: coefficient_half = 18'sd26026;
            8'd138: coefficient_half = 18'sd26708;
            8'd139: coefficient_half = 18'sd27392;
            8'd140: coefficient_half = 18'sd28078;
            8'd141: coefficient_half = 18'sd28765;
            8'd142: coefficient_half = 18'sd29453;
            8'd143: coefficient_half = 18'sd30141;
            8'd144: coefficient_half = 18'sd30830;
            8'd145: coefficient_half = 18'sd31518;
            8'd146: coefficient_half = 18'sd32205;
            8'd147: coefficient_half = 18'sd32890;
            8'd148: coefficient_half = 18'sd33574;
            8'd149: coefficient_half = 18'sd34255;
            8'd150: coefficient_half = 18'sd34934;
            8'd151: coefficient_half = 18'sd35609;
            8'd152: coefficient_half = 18'sd36280;
            8'd153: coefficient_half = 18'sd36947;
            8'd154: coefficient_half = 18'sd37609;
            8'd155: coefficient_half = 18'sd38266;
            8'd156: coefficient_half = 18'sd38916;
            8'd157: coefficient_half = 18'sd39561;
            8'd158: coefficient_half = 18'sd40198;
            8'd159: coefficient_half = 18'sd40829;
            8'd160: coefficient_half = 18'sd41451;
            8'd161: coefficient_half = 18'sd42065;
            8'd162: coefficient_half = 18'sd42671;
            8'd163: coefficient_half = 18'sd43267;
            8'd164: coefficient_half = 18'sd43853;
            8'd165: coefficient_half = 18'sd44429;
            8'd166: coefficient_half = 18'sd44995;
            8'd167: coefficient_half = 18'sd45549;
            8'd168: coefficient_half = 18'sd46092;
            8'd169: coefficient_half = 18'sd46623;
            8'd170: coefficient_half = 18'sd47141;
            8'd171: coefficient_half = 18'sd47647;
            8'd172: coefficient_half = 18'sd48139;
            8'd173: coefficient_half = 18'sd48617;
            8'd174: coefficient_half = 18'sd49082;
            8'd175: coefficient_half = 18'sd49532;
            8'd176: coefficient_half = 18'sd49967;
            8'd177: coefficient_half = 18'sd50386;
            8'd178: coefficient_half = 18'sd50791;
            8'd179: coefficient_half = 18'sd51179;
            8'd180: coefficient_half = 18'sd51551;
            8'd181: coefficient_half = 18'sd51906;
            8'd182: coefficient_half = 18'sd52245;
            8'd183: coefficient_half = 18'sd52566;
            8'd184: coefficient_half = 18'sd52870;
            8'd185: coefficient_half = 18'sd53156;
            8'd186: coefficient_half = 18'sd53425;
            8'd187: coefficient_half = 18'sd53675;
            8'd188: coefficient_half = 18'sd53906;
            8'd189: coefficient_half = 18'sd54119;
            8'd190: coefficient_half = 18'sd54314;
            8'd191: coefficient_half = 18'sd54489;
            8'd192: coefficient_half = 18'sd54645;
            8'd193: coefficient_half = 18'sd54783;
            8'd194: coefficient_half = 18'sd54900;
            8'd195: coefficient_half = 18'sd54998;
            8'd196: coefficient_half = 18'sd55077;
            8'd197: coefficient_half = 18'sd55136;
            8'd198: coefficient_half = 18'sd55176;
            8'd199: coefficient_half = 18'sd55195;
            default: coefficient_half = '0;
            endcase
        end
    endfunction

    function automatic logic signed [COEF_W-1:0] coefficient(
        input logic [8:0] index
    );
        logic [8:0] mirror_index;
        begin
            if (index < 9'd200)
                coefficient = coefficient_half(index[7:0]);
            else begin
                mirror_index = 9'd399 - index;
                coefficient = coefficient_half(mirror_index[7:0]);
            end
        end
    endfunction

    function automatic logic signed [ACC_W-1:0] extend_product(
        input logic signed [PRODUCT_W-1:0] value
    );
        begin
            extend_product = {{(ACC_W-PRODUCT_W){value[PRODUCT_W-1]}}, value};
        end
    endfunction

    initial begin
        for (coef_index = 0; coef_index < 400; coef_index = coef_index + 1)
            coeff_rom[coef_index] = coefficient(coef_index);
    end

    function automatic logic signed [DATA_W-1:0] saturate_sample(
        input logic signed [ACC_W-1:0] value
    );
        logic signed [ACC_W-1:0] scaled;
        logic signed [ACC_W-1:0] maximum;
        logic signed [ACC_W-1:0] minimum;
        begin
            scaled = value >>> COEF_FRAC;
            maximum = ({{(ACC_W-1){1'b0}}, 1'b1} << (DATA_W-1)) - 1'b1;
            minimum = -({{(ACC_W-1){1'b0}}, 1'b1} << (DATA_W-1));
            if (scaled > maximum)
                saturate_sample = {1'b0, {(DATA_W-1){1'b1}}};
            else if (scaled < minimum)
                saturate_sample = {1'b1, {(DATA_W-1){1'b0}}};
            else
                saturate_sample = scaled[DATA_W-1:0];
        end
    endfunction

    assign in_ready = !active || (phase == INTERP_FACTOR-1);

    // 每个高速周期只计算当前相位的4个有效乘积，等价于插零后400抽头普通FIR。
    always_comb begin
        phase_sum = '0;
        for (lane = 0; lane < TAPS_PER_PHASE; lane = lane + 1) begin
            phase_coef[lane] = coeff_rom[phase + lane * INTERP_FACTOR];
            phase_product[lane] = history[lane] * phase_coef[lane];
            phase_sum = phase_sum + extend_product(phase_product[lane]);
        end
        // 与现有FIR保持一致：增加半LSB后算术右移，负数半整数向正方向取整。
        rounded_sum = phase_sum + ({{(ACC_W-1){1'b0}}, 1'b1} << (COEF_FRAC-1));
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            active    <= 1'b0;
            phase     <= '0;
            data_out  <= '0;
            out_valid <= 1'b0;
            overflow  <= 1'b0;
            for (reset_index = 0; reset_index < TAPS_PER_PHASE; reset_index = reset_index + 1)
                history[reset_index] <= '0;
        end else begin
            out_valid <= 1'b0;

            if (active) begin
                data_out  <= saturate_sample(rounded_sum);
                out_valid <= 1'b1;

                if (phase == INTERP_FACTOR-1) begin
                    if (in_valid) begin
                        history[3] <= history[2];
                        history[2] <= history[1];
                        history[1] <= history[0];
                        history[0] <= data_in;
                        phase      <= '0;
                        active     <= 1'b1;
                    end else begin
                        phase  <= '0;
                        active <= 1'b0;
                    end
                end else begin
                    phase <= phase + 1'b1;
                    if (in_valid)
                        overflow <= 1'b1;
                end
            end else if (in_valid) begin
                history[3] <= history[2];
                history[2] <= history[1];
                history[1] <= history[0];
                history[0] <= data_in;
                phase      <= '0;
                active     <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
