// ============================================================================
// 模块名称：ps_bram_subsystem_wrapper
//
// 功能：
//   对Vivado Block Design `ps_bram_subsystem_bd`提供稳定、可在完整PL顶层中例化
//   的HDL边界。PS只经三块双口BRAM与业务PL交换批量数据：
//     1. IQ BRAM：PL写，PS读；
//     2. FIR系数BRAM：PS写，PL读；
//     3. 参数BRAM：PS写，PL读。
//
// 使用规则：
//   - 三组addr均为“各自BRAM窗口内”的32位字节偏移，不是0x4000_0000等
//     AXI绝对地址；地址必须4字节对齐。第n个32-bit word使用(n << 2)。
//   - iq_pl_we按字节有效。写完整word时置4'b1111；iq_pl_en和任一we位
//     同时有效时，在iq_pl_clk上升沿写入。
//   - FIR/参数BRAM为同步读：在对应clk上升沿采入有效en和addr，rdata在该
//     次上升沿后更新；使用者应在下一拍采样。
//   - *_pl_rst仅复位BRAM端口输出状态，不会清空存储阵列。
//   - Port A属于PS FCLK0 100 MHz域，Port B允许使用独立业务时钟。跨时钟
//     的整块数据一致性必须由STATUS/GENERATION发布协议保证；禁止两侧同时
//     写同一块BRAM，也禁止在发布期间消费尚未完成的payload。
//
// 集成方式：
//   本文件与脚本生成的ps_bram_subsystem_bd.bd共同加入最终Vivado工程。
//   DDR和FIXED_IO直接提升到板级顶层；业务PL只连接下方三组角色受限端口。
// ============================================================================
`timescale 1ns/1ps

module ps_bram_subsystem_wrapper (
    // Zynq PS DDR3与固定MIO。作为完整顶层时原样提升为板级端口。
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,

    // IQ BRAM Port B：PL唯一写者。窗口0x0000~0x7FFC，共8192 words。
    input  wire        iq_pl_clk,
    input  wire        iq_pl_rst,
    input  wire        iq_pl_en,
    input  wire [31:0] iq_pl_addr,
    input  wire [3:0]  iq_pl_we,
    input  wire [31:0] iq_pl_wdata,

    // FIR BRAM Port B：PL只读。窗口0x000~0xFFC，共1024 words。
    input  wire        fir_pl_clk,
    input  wire        fir_pl_rst,
    input  wire        fir_pl_en,
    input  wire [31:0] fir_pl_addr,
    output wire [31:0] fir_pl_rdata,

    // 参数BRAM Port B：PL只读。参数表布局尚未冻结，物理窗口先固定为4 KiB。
    input  wire        param_pl_clk,
    input  wire        param_pl_rst,
    input  wire        param_pl_en,
    input  wire [31:0] param_pl_addr,
    output wire [31:0] param_pl_rdata
);

    ps_bram_subsystem_bd u_ps_bram_subsystem_bd (
        .DDR_addr          (DDR_addr),
        .DDR_ba            (DDR_ba),
        .DDR_cas_n         (DDR_cas_n),
        .DDR_ck_n          (DDR_ck_n),
        .DDR_ck_p          (DDR_ck_p),
        .DDR_cke           (DDR_cke),
        .DDR_cs_n          (DDR_cs_n),
        .DDR_dm            (DDR_dm),
        .DDR_dq            (DDR_dq),
        .DDR_dqs_n         (DDR_dqs_n),
        .DDR_dqs_p         (DDR_dqs_p),
        .DDR_odt           (DDR_odt),
        .DDR_ras_n         (DDR_ras_n),
        .DDR_reset_n       (DDR_reset_n),
        .DDR_we_n          (DDR_we_n),
        .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio      (FIXED_IO_mio),
        .FIXED_IO_ps_clk   (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb  (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb),
        .iq_pl_clk         (iq_pl_clk),
        .iq_pl_rst         (iq_pl_rst),
        .iq_pl_en          (iq_pl_en),
        .iq_pl_addr        (iq_pl_addr),
        .iq_pl_we          (iq_pl_we),
        .iq_pl_wdata       (iq_pl_wdata),
        .fir_pl_clk        (fir_pl_clk),
        .fir_pl_rst        (fir_pl_rst),
        .fir_pl_en         (fir_pl_en),
        .fir_pl_addr       (fir_pl_addr),
        .fir_pl_rdata      (fir_pl_rdata),
        .param_pl_clk      (param_pl_clk),
        .param_pl_rst      (param_pl_rst),
        .param_pl_en       (param_pl_en),
        .param_pl_addr     (param_pl_addr),
        .param_pl_rdata    (param_pl_rdata)
    );

endmodule
