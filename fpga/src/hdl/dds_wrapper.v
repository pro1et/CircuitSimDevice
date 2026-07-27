`timescale 1ns / 1ps

`include "params.vh"

// ============================================================================
// 模块名称：dds_wrapper
//
// 主要功能：
//   封装 Xilinx DDS Compiler IP，把 IP 的 AXIS 输出整理为本工程内部统一使用的
//   dds_valid、dds_sine_data、dds_cosine_data、dds_phase_valid 和 dds_phase_data。
//
// 使用方法：
//   1. 将 dds_freq_ctrl 的 dds_cfg_tvalid/dds_cfg_tdata 接入本模块配置端口。
//   2. 将 dds_sine_data/dds_cosine_data 接到 mode_router 作为 DAC 波形源。
//   3. 将 dds_sine_data/dds_cosine_data/dds_phase_data 接到 sweep_iq_demod，
//      作为 I/Q 解调参考和 DDS 周期边界。
//
// 连接说明：
//   clk <- DDS IP aclk，必须与 dds_freq_ctrl 和下游采样逻辑同域。
//   dds_cfg_* <- dds_freq_ctrl。
//   dds_*     -> mode_router、sweep_iq_demod 或 ILA。
//
// 时钟与复位：
//   所有输出寄存器同步到 clk。rst_n 为异步低有效复位，只复位 wrapper 输出
//   寄存器；DDS IP 本体没有在此 wrapper 中暴露独立复位端口。
//
// 输入格式：
//   dds_cfg_tdata 为 32 bit DDS 配置字，低位放置 phase increment。
//
// 输出格式：
//   DDS IP 当前打包格式为 m_axis_data_tdata[15:8]=sine，[7:0]=cosine。两路
//   原始 DDS_OUTPUT_W 位 signed 数据会左移扩展到 DATA_W 位 signed 数据。
//   dds_phase_data 为 DDS IP 输出的 32 bit 相位字。
//
// 握手时序：
//   dds_cfg_tvalid 为单周期配置脉冲。dds_valid 为高时 sine/cosine 同周期有效；
//   dds_phase_valid 为高时 phase 同周期有效。
//
// 参数说明：
//   DATA_W 为工程内部采样位宽。DDS_OUTPUT_W 必须等于 DDS IP 每路 waveform 位宽。
//
// 错误行为：
//   本模块不检测 DDS IP 配置错误；若配置接口不匹配，表现为输出频率或波形异常。
//
// 使用限制：
//   当前 IP 没有显式 tready/config ready 端口，所以上游必须按 dds_freq_ctrl 的
//   单周期配置方式使用。
// ============================================================================
module dds_wrapper #(
    parameter integer DATA_W       = `BOARD_DATA_W,
    parameter integer DDS_OUTPUT_W = `DDS_OUTPUT_W
) (
    // 模块工作时钟，连接 DDS IP aclk，通常为 sample_clk_30m。
    input  wire      clk,
    // 异步低有效复位，仅清零 wrapper 输出寄存器。
    input  wire      rst_n,
    // DDS 配置有效输入，来自 dds_freq_ctrl，单周期脉冲。
    input  wire      dds_cfg_tvalid,
    // DDS 32 bit 配置字，低位对齐的相位增量。
    input  wire [31:0] dds_cfg_tdata,
    // DDS 波形有效输出；为高时 sine/cosine 同周期有效。
    output reg       dds_valid,
    // DDS sine signed 采样，已由 DDS_OUTPUT_W 扩展到 DATA_W。
    output reg signed [DATA_W-1:0] dds_sine_data,
    // DDS cosine signed 采样，已由 DDS_OUTPUT_W 扩展到 DATA_W。
    output reg signed [DATA_W-1:0] dds_cosine_data,
    // DDS 相位有效输出；为高时 dds_phase_data 同周期有效。
    output reg       dds_phase_valid,
    // DDS 32 bit 相位输出；sweep_iq_demod 用回绕判断周期边界。
    output reg [31:0] dds_phase_data
);

    wire       m_axis_data_tvalid;
    wire [15:0] m_axis_data_tdata;
    wire       m_axis_phase_tvalid;
    wire [31:0] m_axis_phase_tdata;

    // 将 DDS IP 原始输出位宽扩展到板级采样数据位宽。
    function signed [DATA_W-1:0] expand_wave;
        input [DDS_OUTPUT_W-1:0] value;
        begin
            expand_wave = $signed({value, {(DATA_W-DDS_OUTPUT_W){1'b0}}});
        end
    endfunction

    // Xilinx DDS Compiler IP:
    //   m_axis_data_tdata[15:8] -> sine
    //   m_axis_data_tdata[7:0]  -> cosine
    dds_compiler_0 u_dds_compiler_0 (
        .aclk                (clk),
        .s_axis_config_tvalid(dds_cfg_tvalid),
        .s_axis_config_tdata (dds_cfg_tdata),
        .m_axis_data_tvalid  (m_axis_data_tvalid),
        .m_axis_data_tdata   (m_axis_data_tdata),
        .m_axis_phase_tvalid (m_axis_phase_tvalid),
        .m_axis_phase_tdata  (m_axis_phase_tdata)
    );

    // 对 DDS 输出打一拍，让下游模块看到稳定、统一的本地接口。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dds_valid       <= 1'b0;
            dds_sine_data   <= {DATA_W{1'b0}};
            dds_cosine_data <= {DATA_W{1'b0}};
            dds_phase_valid <= 1'b0;
            dds_phase_data  <= 32'd0;
        end else begin
            dds_valid <= m_axis_data_tvalid;
            dds_phase_valid <= m_axis_phase_tvalid;

            if (m_axis_data_tvalid) begin
                // 将 DDS 打包输出拆成 sine/cosine 两路。
                dds_sine_data   <= expand_wave(m_axis_data_tdata[15:8]);
                dds_cosine_data <= expand_wave(m_axis_data_tdata[7:0]);
            end
            // 相位输出供扫频逻辑做周期对齐。
            if (m_axis_phase_tvalid)
                dds_phase_data <= m_axis_phase_tdata;
        end
    end

endmodule
