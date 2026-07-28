`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// 模块名称：coef_bram_tb
//
// 主要功能：
//   自检coef_bram的COE初值、双时钟读访问、A口逐字节写、非法地址阻止，并联合
//   fir_coef_loader验证协议头和129个Q1.31系数可以从B口完整装载。
//
// 使用方法：
//   从仓库work目录运行fpga/scripts/sim_coef_bram.tcl。
//
// 连接说明：
//   实例化coef_bram和fir_coef_loader；先由测试进程控制B口，随后切换给loader。
//
// 时钟与复位：
//   A口时钟周期10 ns，B口及loader时钟周期14 ns；两者频率和相位不同。
//
// 输入格式：
//   地址均为32位字节地址；写数据和COE初值均按32位原始字比较。
//
// 输出格式：
//   test_passed为1表示全部断言和loader联合检查通过。
//
// 握手时序：
//   读请求保持一个对应端口时钟周期，并在接收请求的上升沿后检查一拍读结果。
//
// 参数说明：
//   loader轮询周期缩短为4拍，仅用于加速仿真，不改变硬件默认值。
//
// 错误行为：
//   任一数据、时序、地址或系数顺序不匹配立即调用$fatal终止仿真。
//
// 使用限制：
//   验证使用fir_bandpass_10k_25k.coe；关键抽头按MATLAB生成值检查，并利用线性相位
//   FIR的系数对称性检查全部129个装载字。若重新生成系数，需同步修改关键期望值。
// ============================================================================

module coef_bram_tb;

    timeunit 1ns;
    timeprecision 1ps;

    logic        clka;
    logic        rsta;
    logic        ena;
    logic [3:0]  wea;
    logic [31:0] addra;
    logic [31:0] dina;
    logic [31:0] douta;
    logic        addra_error;

    logic        clkb;
    logic        tb_rstb;
    logic        tb_enb;
    logic [3:0]  tb_web;
    logic [31:0] tb_addrb;
    logic [31:0] tb_dinb;
    logic [31:0] doutb;
    logic        addrb_error;

    logic        use_loader;
    logic        loader_rst_n;
    logic        loader_clkb;
    logic        loader_rstb;
    logic        loader_enb;
    logic [3:0]  loader_web;
    logic [31:0] loader_addrb;
    logic [31:0] loader_dinb;
    logic        coef_we;
    logic [7:0]  coef_addr;
    logic [31:0] coef_wdata;
    logic        coef_clear;
    logic        coef_ready;
    logic        coef_error;
    logic [31:0] coef_generation;
    logic        test_passed;

    logic        bram_rstb;
    logic        bram_enb;
    logic [3:0]  bram_web;
    logic [31:0] bram_addrb;
    logic [31:0] bram_dinb;

    int unsigned loaded_count;
    int unsigned timeout_count;
    integer coefficient_index;
    logic [31:0] loaded_coefficient [0:128];

    assign bram_rstb  = use_loader ? loader_rstb  : tb_rstb;
    assign bram_enb   = use_loader ? loader_enb   : tb_enb;
    assign bram_web   = use_loader ? loader_web   : tb_web;
    assign bram_addrb = use_loader ? loader_addrb : tb_addrb;
    assign bram_dinb  = use_loader ? loader_dinb  : tb_dinb;

    coef_bram dut (
        .clka        (clka),
        .rsta        (rsta),
        .ena         (ena),
        .wea         (wea),
        .addra       (addra),
        .dina        (dina),
        .douta       (douta),
        .addra_error (addra_error),
        .clkb        (clkb),
        .rstb        (bram_rstb),
        .enb         (bram_enb),
        .web         (bram_web),
        .addrb       (bram_addrb),
        .dinb        (bram_dinb),
        .doutb       (doutb),
        .addrb_error (addrb_error)
    );

    fir_coef_loader #(
        .TAP_COUNT  (129),
        .POLL_CYCLES(4)
    ) u_loader (
        .clk             (clkb),
        .rst_n           (loader_rst_n),
        .bram_clkb       (loader_clkb),
        .bram_rstb       (loader_rstb),
        .bram_enb        (loader_enb),
        .bram_web        (loader_web),
        .bram_addrb      (loader_addrb),
        .bram_dinb       (loader_dinb),
        .bram_doutb      (doutb),
        .coef_we         (coef_we),
        .coef_addr       (coef_addr),
        .coef_wdata      (coef_wdata),
        .coef_clear      (coef_clear),
        .coef_ready      (coef_ready),
        .coef_error      (coef_error),
        .coef_generation (coef_generation)
    );

    always #5ns clka = ~clka;
    always #7ns clkb = ~clkb;

    task automatic read_a(input logic [31:0] address,
                          input logic [31:0] expected);
        begin
            @(negedge clka);
            ena   = 1'b1;
            wea   = 4'b0000;
            addra = address;
            @(posedge clka);
            #1ns;
            assert (douta === expected)
                else $fatal(1, "A口读取错误：地址=%08h，实际=%08h，期望=%08h",
                            address, douta, expected);
            @(negedge clka);
            ena = 1'b0;
        end
    endtask

    task automatic read_b(input logic [31:0] address,
                          input logic [31:0] expected);
        begin
            @(negedge clkb);
            tb_enb   = 1'b1;
            tb_web   = 4'b0000;
            tb_addrb = address;
            @(posedge clkb);
            #1ns;
            assert (doutb === expected)
                else $fatal(1, "B口读取错误：地址=%08h，实际=%08h，期望=%08h",
                            address, doutb, expected);
            @(negedge clkb);
            tb_enb = 1'b0;
        end
    endtask

    always @(posedge clkb) begin
        if (!loader_rst_n) begin
            loaded_count <= 0;
        end else if (coef_we) begin
            assert (coef_addr == loaded_count[7:0])
                else $fatal(1, "系数地址顺序错误：实际=%0d，期望=%0d",
                            coef_addr, loaded_count);
            assert (!$isunknown(coef_wdata))
                else $fatal(1, "系数数据包含未知值：tap=%0d", loaded_count);
            if (loaded_count == 0)
                assert (coef_wdata === 32'h0000_753E)
                    else $fatal(1, "首抽头错误：实际=%08h", coef_wdata);
            if (loaded_count == 64)
                assert (coef_wdata === 32'h0E87_684F)
                    else $fatal(1, "中心抽头错误：实际=%08h", coef_wdata);
            if (loaded_count == 128)
                assert (coef_wdata === 32'h0000_753E)
                    else $fatal(1, "末抽头错误：实际=%08h", coef_wdata);
            loaded_coefficient[loaded_count] <= coef_wdata;
            loaded_count <= loaded_count + 1;
        end
    end

    initial begin
        test_passed = 1'b0;
        clka        = 1'b0;
        clkb        = 1'b0;
        rsta        = 1'b1;
        ena         = 1'b0;
        wea         = 4'b0000;
        addra       = 32'd0;
        dina        = 32'd0;
        tb_rstb     = 1'b1;
        tb_enb      = 1'b0;
        tb_web      = 4'b0000;
        tb_addrb    = 32'd0;
        tb_dinb     = 32'd0;
        use_loader  = 1'b0;
        loader_rst_n = 1'b0;

        repeat (3) @(posedge clka);
        rsta = 1'b0;
        repeat (3) @(posedge clkb);
        tb_rstb = 1'b0;

        read_a(32'h0000_0000, 32'h434F_4546);
        read_b(32'h0000_0004, 32'h0001_0000);
        read_b(32'h0000_0040, 32'h0000_753E);
        read_b(32'h0000_0044, 32'h0002_CFC5);

        // A口只改写payload[4]的第0、2字节，验证逐字节写使能。
        @(negedge clka);
        ena   = 1'b1;
        wea   = 4'b0101;
        addra = 32'h0000_0050;
        dina  = 32'hAABB_CCDD;
        @(posedge clka);
        @(negedge clka);
        ena = 1'b0;
        wea = 4'b0000;
        read_b(32'h0000_0050, 32'h00BB_02DD);

        // 恢复被逐字节写测试修改的tap[4]，确保随后装载的是原始带通系数镜像。
        @(negedge clka);
        ena   = 1'b1;
        wea   = 4'b1111;
        addra = 32'h0000_0050;
        dina  = 32'h000C_0200;
        @(posedge clka);
        @(negedge clka);
        ena = 1'b0;
        wea = 4'b0000;
        read_b(32'h0000_0050, 32'h000C_0200);

        // A口越界、B口未对齐访问都必须被拒绝并返回0。
        @(negedge clka);
        ena   = 1'b1;
        addra = 32'h0000_1000;
        #1ps;
        assert (addra_error) else $fatal(1, "A口越界未报告错误");
        @(posedge clka);
        #1ns;
        assert (douta == 32'd0) else $fatal(1, "A口越界读取未返回0");
        @(negedge clka);
        ena = 1'b0;

        @(negedge clkb);
        tb_enb   = 1'b1;
        tb_addrb = 32'h0000_0042;
        #1ps;
        assert (addrb_error) else $fatal(1, "B口未对齐访问未报告错误");
        @(posedge clkb);
        #1ns;
        assert (doutb == 32'd0) else $fatal(1, "B口非法读取未返回0");
        @(negedge clkb);
        tb_enb = 1'b0;

        // B口切换给loader；切换时loader仍在复位，避免产生半拍请求。
        use_loader = 1'b1;
        repeat (2) @(posedge clkb);
        loader_rst_n = 1'b1;

        timeout_count = 0;
        while (!coef_ready && timeout_count < 1000) begin
            @(posedge clkb);
            timeout_count = timeout_count + 1;
        end
        #1ns;
        assert (coef_ready) else $fatal(1, "fir_coef_loader装载超时");
        assert (!coef_error) else $fatal(1, "fir_coef_loader错误标志异常");
        assert (coef_generation == 32'd1)
            else $fatal(1, "generation错误：实际=%0d", coef_generation);
        assert (loaded_count == 129)
            else $fatal(1, "装载系数数量错误：实际=%0d，期望=129", loaded_count);
        for (coefficient_index = 0; coefficient_index < 65;
             coefficient_index = coefficient_index + 1) begin
            assert (loaded_coefficient[coefficient_index] ===
                    loaded_coefficient[128-coefficient_index])
                else $fatal(1, "线性相位系数不对称：tap=%0d和tap=%0d",
                            coefficient_index, 128-coefficient_index);
        end

        test_passed = 1'b1;
        $display("TEST PASSED: coef_bram双口、COE初值和129个FIR系数装载验证通过");
        $finish;
    end

endmodule

`default_nettype wire
