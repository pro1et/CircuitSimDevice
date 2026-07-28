`timescale 1ns/1ps
`default_nettype none

`include "dds_param_protocol.vh"

// 参数 BRAM reader 自检：同步读模型、合法发布、重复 generation、协议错误和复位重载。
module dds_param_reader_tb;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic bram_en;
    logic [31:0] bram_addr;
    logic [31:0] bram_rdata = 32'd0;
    logic [31:0] dds_freq_hz;
    logic dds_freq_we;
    logic [31:0] active_generation;
    logic protocol_error;
    logic [31:0] mem [0:1023];
    integer update_count = 0;
    logic test_passed = 1'b0;

    always #5 clk = ~clk;

    // 与 Block Memory Generator Port B 一致：地址在上升沿采入，数据随后更新。
    always_ff @(posedge clk) begin
        if (bram_en)
            bram_rdata <= mem[bram_addr[11:2]];
        if (dds_freq_we)
            update_count <= update_count + 1;
    end

    dds_param_reader #(
        .POLL_CYCLES(2)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .bram_en          (bram_en),
        .bram_addr        (bram_addr),
        .bram_rdata       (bram_rdata),
        .dds_freq_hz      (dds_freq_hz),
        .dds_freq_we      (dds_freq_we),
        .active_generation(active_generation),
        .protocol_error   (protocol_error)
    );

    task automatic write_snapshot(
        input logic [31:0] generation,
        input logic [31:0] frequency_hz,
        input logic [31:0] magic,
        input logic [1:0]  final_status
    );
        begin
            mem[`DDS_PARAM_ADDR_STATUS >> 2]     = 32'd0;
            mem[`DDS_PARAM_ADDR_MAGIC >> 2]      = magic;
            mem[`DDS_PARAM_ADDR_VERSION >> 2]    = `DDS_PARAM_VERSION;
            mem[`DDS_PARAM_ADDR_WORD_COUNT >> 2] = `DDS_PARAM_WORD_COUNT;
            mem[`DDS_PARAM_ADDR_FORMAT >> 2]     = `DDS_PARAM_FORMAT_FREQ_HZ;
            mem[`DDS_PARAM_ADDR_FREQ_HZ >> 2]    = frequency_hz;
            mem[`DDS_PARAM_ADDR_GENERATION >> 2] = generation;
            mem[`DDS_PARAM_ADDR_STATUS >> 2]     = {30'd0, final_status};
        end
    endtask

    task automatic expect_update(input logic [31:0] expected_hz);
        integer cycles;
        logic observed;
        begin
            observed = 1'b0;
            for (cycles = 0; cycles < 300; cycles = cycles + 1) begin
                @(posedge clk);
                if (dds_freq_we) begin
                    assert (dds_freq_hz == expected_hz)
                        else $fatal(1, "频率错误：actual=%0d expected=%0d", dds_freq_hz, expected_hz);
                    observed = 1'b1;
                    cycles = 300;
                end
            end
            assert (observed) else $fatal(1, "等待频率 %0d 更新超时", expected_hz);
        end
    endtask

    task automatic expect_no_update(input integer cycles);
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge clk);
                assert (!dds_freq_we) else $fatal(1, "重复或非法快照产生了更新脉冲");
            end
        end
    endtask

    task automatic expect_error;
        integer cycles;
        logic observed;
        begin
            observed = 1'b0;
            for (cycles = 0; cycles < 300; cycles = cycles + 1) begin
                @(posedge clk);
                if (protocol_error) begin
                    observed = 1'b1;
                    cycles = 300;
                end
            end
            assert (observed) else $fatal(1, "等待 protocol_error 超时");
        end
    endtask

    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1)
            mem[i] = 32'd0;

        repeat (4) @(posedge clk);
        rst_n <= 1'b1;
        assert (dds_freq_hz == 32'd500) else $fatal(1, "复位默认频率不是500 Hz");

        // BUSY 不得改变默认频率。
        write_snapshot(32'd1, 32'd10_000, `DDS_PARAM_MAGIC, `DDS_PARAM_STATUS_BUSY);
        expect_no_update(50);

        // 第一代合法快照只提交一次。
        write_snapshot(32'd1, 32'd10_000, `DDS_PARAM_MAGIC, `DDS_PARAM_STATUS_VALID);
        expect_update(32'd10_000);
        expect_no_update(80);
        assert (active_generation == 32'd1) else $fatal(1, "generation 1 未生效");

        // 错误 MAGIC 不得覆盖上一频率，并必须报告协议错误。
        write_snapshot(32'd2, 32'd25_000, 32'hDEAD_BEEF, `DDS_PARAM_STATUS_VALID);
        expect_error();
        assert (dds_freq_hz == 32'd10_000) else $fatal(1, "非法快照覆盖了有效频率");

        // 修复同一代快照后应接受并清除错误。
        write_snapshot(32'd2, 32'd25_000, `DDS_PARAM_MAGIC, `DDS_PARAM_STATUS_VALID);
        expect_update(32'd25_000);
        @(posedge clk);
        assert (!protocol_error) else $fatal(1, "合法快照未清除协议错误");

        // 超上限频率不得提交。
        write_snapshot(32'd3, 32'd1_000_001, `DDS_PARAM_MAGIC, `DDS_PARAM_STATUS_VALID);
        expect_error();
        assert (dds_freq_hz == 32'd25_000) else $fatal(1, "越界频率被错误接受");

        // reader复位不清BRAM；恢复合法快照后可重新加载当前generation。
        write_snapshot(32'd2, 32'd25_000, `DDS_PARAM_MAGIC, `DDS_PARAM_STATUS_VALID);
        rst_n <= 1'b0;
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        expect_update(32'd25_000);

        test_passed = 1'b1;
        $display("DDS_PARAM_READER_TEST_PASSED updates=%0d", update_count);
        $finish;
    end

endmodule

`default_nettype wire
