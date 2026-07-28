`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：coef_bram
//
// 主要功能：
//   封装一块32位、4 KiB的真双口Block RAM，保存共享协议头和FIR的Q1.31系数。
//   存储器本体由Vivado Block Memory Generator生成的coef_bram_ip实现，当前可由
//   COE文件初始化；接入PS后保持本模块不变，由AXI BRAM Controller使用A口更新。
//
// 使用方法：
//   1. 在vivado2022环境中运行fpga/scripts/generate_coef_bram_ip.tcl生成IP。
//   2. 当前纯PL测试可将A口保持禁用，COE中的合法快照会由fir_coef_loader从B口读取。
//   3. 接入PS后，将AXI BRAM Controller原生BRAM端口连接A口。
//   4. 将fir_coef_loader的bram_*端口连接B口；B口写使能固定为0。
//
// 连接说明：
//   clka/rsta/ena/wea/addra/dina/douta <- PS侧AXI BRAM Controller原生端口
//   clkb/rstb/enb/web/addrb/dinb/doutb <- PL侧fir_coef_loader的bram_*端口
//   addra_error/addrb_error             -> 顶层状态寄存器或ILA，可不连接
//
// 时钟与复位：
//   A、B口允许使用彼此异步的时钟。rsta、rstb均为对应端口时钟域的高有效同步
//   复位，只复位输出寄存状态，不清除BRAM内容。跨时钟域的数据一致性由共享BRAM
//   的GENERATION和STATUS发布协议保证，不能把双口BRAM本身当作逐字握手。
//
// 输入格式：
//   两个端口均使用32位小端数据和32位字节地址，合法范围0x000~0xFFC且必须4字节
//   对齐。wea/web每一位控制对应8位字节；当前B口消费者必须驱动web=4'b0000。
//
// 输出格式：
//   douta/doutb为32位原始字。协议头位于0x00~0x3C，payload[0]从0x40开始；
//   FIR系数为signed Q1.31，但BRAM本身不解释符号和定点格式。
//
// 握手时序：
//   端口使能为高的时钟上升沿接收地址和写数据；读数据在该上升沿后一拍有效。
//   端口使能为低时保持最近一次有效读数据。读写同一端口同一地址采用READ_FIRST。
//
// 参数说明：
//   容量和数据宽度由PS共享协议固定为1024 x 32 bit，不提供运行时配置。
//
// 错误行为：
//   使能期间若地址越界或未按4字节对齐，对应addr*_error在当拍拉高，访问被阻止，
//   读输出变为0。复位不会删除COE初值或PS已写入内容。
//
// 使用限制：
//   两端不得同时写同一地址；当前协议规定PS是唯一写者、PL只读，因此web必须为0。
//   本模块依赖Xilinx coef_bram_ip，目标器件或IP配置改变后必须重新综合验证。
// ============================================================================

module coef_bram (
    input  wire  logic        clka,         // A口时钟，未来连接AXI BRAM Controller时钟
    input  wire  logic        rsta,         // A口高有效同步复位，不清除存储内容
    input  wire  logic        ena,          // A口访问使能，高电平时接收本拍请求
    input  wire  logic [3:0]  wea,          // A口逐字节写使能，4'b0000表示只读
    input  wire  logic [31:0] addra,        // A口32位字节地址，范围0x000~0xFFC且4字节对齐
    input  wire  logic [31:0] dina,         // A口写数据，32位原始字
    output       logic [31:0] douta,        // A口读数据，请求后一拍有效，无使能时保持
    output wire  logic        addra_error,  // A口请求地址非法，当拍组合有效

    input  wire  logic        clkb,         // B口时钟，连接fir_coef_loader工作时钟
    input  wire  logic        rstb,         // B口高有效同步复位，不清除存储内容
    input  wire  logic        enb,          // B口访问使能，高电平时接收本拍请求
    input  wire  logic [3:0]  web,          // B口逐字节写使能，当前fir_coef_loader固定为0
    input  wire  logic [31:0] addrb,        // B口32位字节地址，范围0x000~0xFFC且4字节对齐
    input  wire  logic [31:0] dinb,         // B口写数据，当前fir_coef_loader固定为0
    output       logic [31:0] doutb,        // B口读数据，请求后一拍有效，无使能时保持
    output wire  logic        addrb_error   // B口请求地址非法，当拍组合有效
);

    localparam int unsigned ADDR_W = 10;

    logic [31:0] ip_douta;
    logic [31:0] ip_doutb;
    logic        a_result_valid;
    logic        b_result_valid;
    logic        a_addr_valid;
    logic        b_addr_valid;

    always_comb begin
        a_addr_valid = (addra[31:12] == 20'd0) && (addra[1:0] == 2'b00);
        b_addr_valid = (addrb[31:12] == 20'd0) && (addrb[1:0] == 2'b00);
    end

    assign addra_error = ena && !a_addr_valid;
    assign addrb_error = enb && !b_addr_valid;

    always_ff @(posedge clka) begin
        if (rsta) begin
            a_result_valid <= 1'b0;
        end else if (ena) begin
            a_result_valid <= a_addr_valid;
        end
    end

    always_ff @(posedge clkb) begin
        if (rstb) begin
            b_result_valid <= 1'b0;
        end else if (enb) begin
            b_result_valid <= b_addr_valid;
        end
    end

    always_comb begin
        douta = a_result_valid ? ip_douta : 32'd0;
        doutb = b_result_valid ? ip_doutb : 32'd0;
    end

    coef_bram_ip u_bram (
        .clka  (clka),
        .rsta  (rsta),
        .ena   (ena && a_addr_valid),
        .wea   (wea),
        .addra (addra[ADDR_W+1:2]),
        .dina  (dina),
        .douta (ip_douta),
        .clkb  (clkb),
        .rstb  (rstb),
        .enb   (enb && b_addr_valid),
        .web   (web),
        .addrb (addrb[ADDR_W+1:2]),
        .dinb  (dinb),
        .doutb (ip_doutb)
    );

endmodule

`default_nettype wire
