`timescale 1ns / 1ps

// ============================================================================
// 模块名称：fir_coef_loader
//
// 主要功能：
//   作为 PL 侧的系数 BRAM 消费者，轮询 PS 发布到共享系数 BRAM 的协议头和
//   payload。发现新的稳定 generation 且 STATUS=VALID 后，将 129 个 Q1.31
//   FIR 系数逐个写入 fir_filter。
//
// 使用方法：
//   1. PS 按共享 BRAM 协议写 STATUS=BUSY、header、payload、GENERATION，
//      最后写 STATUS=VALID。
//   2. 本模块周期性轮询系数 BRAM header。
//   3. 当 MAGIC/VERSION/GENERATION/STATUS/TAP_COUNT/FORMAT/SCALE 全部合法时，
//      先拉高 coef_clear 1 个 clk 周期，再从 payload 依次输出 coef_we。
//   4. 全部系数装载完成后，coef_ready 置 1，并更新 coef_generation。
//
// 连接说明：
//   bram_*      -> 系数 BRAM Port B；Port A 由 PS 通过 AXI BRAM Controller 访问。
//   coef_*      -> fir_filter 的系数写接口。
//   coef_ready  -> basic_req_ctrl/mode_router，用于判断 FIR 是否可进入工作模式。
//   coef_error  -> 顶层状态寄存器或 ILA，用于提示系数协议错误。
//
// 时钟与复位：
//   所有端口除 rst_n 外均同步到 clk。rst_n 为异步低有效复位。bram_clkb 直接
//   输出 clk，bram_rstb 为高有效复位。
//
// 输入格式：
//   系数 BRAM header 遵循共享 BRAM 协议：
//   0x00 MAGIC='COEF'，0x04 VERSION=0x00010000，0x08 GENERATION，
//   0x0C STATUS，0x10 TAP_COUNT，0x14 FORMAT，0x18 SCALE。
//   payload 从 0x40 开始，每个 tap 为 signed 32 bit Q1.31。
//
// 输出格式：
//   coef_we 为单周期写脉冲；coef_addr 为 tap 下标；coef_wdata 为 signed Q1.31
//   原始系数字。coef_generation 保存最近一次成功装载的 generation。
//
// 握手时序：
//   原生 BRAM Port B 读数据有寄存延迟，因此状态机使用 *_A 发起读、*_B 检查
//   bram_doutb 的两拍结构。PL 只读系数 BRAM，PS 是唯一写入者。
//
// 参数说明：
//   TAP_COUNT 为期望系数数量，必须与 fir_filter 的 TAP_COUNT 和 PS 发布头一致。
//
// 错误行为：
//   MAGIC 不匹配时认为 PS 尚未发布，回到轮询；VERSION/TAP_COUNT/FORMAT/SCALE
//   不匹配时 coef_error 置 1。下一次合法发布仍可覆盖错误状态。
//
// 使用限制：
//   本模块不向 PS 写 STATUS，也不 ACK。PS/PL 通过 GENERATION 和 STATUS 保证
//   快照一致性，遵守“PS 写、PL 只读”的单写者规则。
// ============================================================================
module fir_coef_loader #(
    parameter integer TAP_COUNT = 129 // 期望 FIR 抽头数量，需与 PS 和 fir_filter 一致。
) (
    // 模块工作时钟，当前连接 30 MHz 采样时钟。
    input  wire                  clk,
    // 异步低有效复位，清零状态机、BRAM 读控制和输出状态。
    input  wire                  rst_n,

    // 系数 BRAM Port B 时钟；直接连接 clk。
    output wire                  bram_clkb,
    // 系数 BRAM Port B 高有效复位；由 ~rst_n 生成。
    output wire                  bram_rstb,
    // 系数 BRAM Port B 使能；读 header/payload 时拉高。
    output reg                   bram_enb,
    // 系数 BRAM Port B 字节写使能；本模块只读，固定为 0。
    output wire [3:0]            bram_web,
    // 系数 BRAM Port B 字节地址，访问 word n 时驱动 n<<2。
    output reg  [31:0]           bram_addrb,
    // 系数 BRAM Port B 写数据；本模块只读，固定为 0。
    output wire [31:0]           bram_dinb,
    // 系数 BRAM Port B 读数据，包含 header 字段或 Q1.31 tap。
    input  wire [31:0]           bram_doutb,

    // FIR 系数写使能，单周期脉冲；连接 fir_filter.coef_we。
    output reg                   coef_we,
    // FIR 系数写地址，即 tap 下标。
    output reg  [7:0]            coef_addr,
    // FIR 系数写数据，signed 32 bit Q1.31。
    output reg  [31:0]           coef_wdata,
    // FIR 系数/状态清零脉冲；装载新一代系数前拉高 1 个 clk。
    output reg                   coef_clear,
    // 至少成功装载过一代合法系数后为高。
    output reg                   coef_ready,
    // 系数协议检查失败标志；下一次成功装载会清零。
    output reg                   coef_error,
    // 最近一次成功装载的 BRAM generation。
    output reg  [31:0]           coef_generation
);
    localparam [31:0] COEFF_MAGIC   = 32'h434F_4546; // "COEF"
    localparam [31:0] VERSION       = 32'h0001_0000;
    localparam [31:0] STATUS_VALID  = 32'h0000_0001;
    localparam [31:0] FORMAT_Q1_31  = 32'd1;

    localparam [31:0] OFF_MAGIC      = 32'h00;
    localparam [31:0] OFF_VERSION    = 32'h04;
    localparam [31:0] OFF_GENERATION = 32'h08;
    localparam [31:0] OFF_STATUS     = 32'h0C;
    localparam [31:0] OFF_TAP_COUNT  = 32'h10;
    localparam [31:0] OFF_FORMAT     = 32'h14;
    localparam [31:0] OFF_SCALE      = 32'h18;
    localparam [31:0] OFF_PAYLOAD    = 32'h40;

    localparam [4:0] ST_IDLE       = 5'd0;
    localparam [4:0] ST_MAGIC_A    = 5'd1;
    localparam [4:0] ST_MAGIC_B    = 5'd2;
    localparam [4:0] ST_VERSION_A  = 5'd3;
    localparam [4:0] ST_VERSION_B  = 5'd4;
    localparam [4:0] ST_GEN_A      = 5'd5;
    localparam [4:0] ST_GEN_B      = 5'd6;
    localparam [4:0] ST_STATUS_A   = 5'd7;
    localparam [4:0] ST_STATUS_B   = 5'd8;
    localparam [4:0] ST_TAPS_A     = 5'd9;
    localparam [4:0] ST_TAPS_B     = 5'd10;
    localparam [4:0] ST_FORMAT_A   = 5'd11;
    localparam [4:0] ST_FORMAT_B   = 5'd12;
    localparam [4:0] ST_SCALE_A    = 5'd13;
    localparam [4:0] ST_SCALE_B    = 5'd14;
    localparam [4:0] ST_COEF_A     = 5'd15;
    localparam [4:0] ST_COEF_B     = 5'd16;
    localparam [4:0] ST_DONE       = 5'd17;
    localparam [4:0] ST_ERROR      = 5'd18;

    reg [4:0] state;
    reg [31:0] poll_count;
    reg [31:0] new_generation;
    reg [7:0] load_index;

    assign bram_clkb = clk;
    assign bram_rstb = ~rst_n;
    assign bram_web  = 4'b0000;
    assign bram_dinb = 32'd0;

    // 原生 BRAM 使用字节地址；读请求后一拍在 bram_doutb 上观察结果。
    task bram_read;
        input [31:0] byte_addr;
        begin
            bram_enb   <= 1'b1;
            bram_addrb <= byte_addr;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            poll_count      <= 32'd0;
            new_generation  <= 32'd0;
            load_index      <= 8'd0;
            bram_enb        <= 1'b0;
            bram_addrb      <= 32'd0;
            coef_we         <= 1'b0;
            coef_addr       <= 8'd0;
            coef_wdata      <= 32'd0;
            coef_clear      <= 1'b0;
            coef_ready      <= 1'b0;
            coef_error      <= 1'b0;
            coef_generation <= 32'd0;
        end else begin
            bram_enb   <= 1'b0;
            coef_we    <= 1'b0;
            coef_clear <= 1'b0;

            case (state)
                ST_IDLE: begin
                    // 低频轮询降低撞上 PS 写入中间态的概率；真正的一致性仍由
                    // STATUS=VALID 和 GENERATION 检查保证。
                    if (poll_count >= 32'd3000000) begin
                        poll_count <= 32'd0;
                        bram_read(OFF_MAGIC);
                        state <= ST_MAGIC_A;
                    end else begin
                        poll_count <= poll_count + 1'b1;
                    end
                end

                ST_MAGIC_A:   begin bram_read(OFF_MAGIC); state <= ST_MAGIC_B; end
                ST_MAGIC_B:   begin if (bram_doutb == COEFF_MAGIC) begin bram_read(OFF_VERSION); state <= ST_VERSION_A; end else state <= ST_IDLE; end
                ST_VERSION_A: begin bram_read(OFF_VERSION); state <= ST_VERSION_B; end
                ST_VERSION_B: begin if (bram_doutb == VERSION) begin bram_read(OFF_GENERATION); state <= ST_GEN_A; end else state <= ST_ERROR; end
                ST_GEN_A:     begin bram_read(OFF_GENERATION); state <= ST_GEN_B; end
                ST_GEN_B: begin
                    new_generation <= bram_doutb;
                    if (bram_doutb == coef_generation)
                        state <= ST_IDLE;
                    else begin
                        bram_read(OFF_STATUS);
                        state <= ST_STATUS_A;
                    end
                end
                ST_STATUS_A: begin bram_read(OFF_STATUS); state <= ST_STATUS_B; end
                ST_STATUS_B: begin
                    if ((bram_doutb & 32'h3) == STATUS_VALID) begin
                        bram_read(OFF_TAP_COUNT);
                        state <= ST_TAPS_A;
                    end else begin
                        state <= ST_IDLE;
                    end
                end
                ST_TAPS_A: begin bram_read(OFF_TAP_COUNT); state <= ST_TAPS_B; end
                ST_TAPS_B: begin
                    if (bram_doutb == TAP_COUNT) begin
                        bram_read(OFF_FORMAT);
                        state <= ST_FORMAT_A;
                    end else begin
                        state <= ST_ERROR;
                    end
                end
                ST_FORMAT_A: begin bram_read(OFF_FORMAT); state <= ST_FORMAT_B; end
                ST_FORMAT_B: begin
                    if (bram_doutb == FORMAT_Q1_31) begin
                        bram_read(OFF_SCALE);
                        state <= ST_SCALE_A;
                    end else begin
                        state <= ST_ERROR;
                    end
                end
                ST_SCALE_A: begin bram_read(OFF_SCALE); state <= ST_SCALE_B; end
                ST_SCALE_B: begin
                    if (bram_doutb == 32'd31) begin
                        coef_clear <= 1'b1;
                        load_index <= 8'd0;
                        bram_read(OFF_PAYLOAD);
                        state <= ST_COEF_A;
                    end else begin
                        state <= ST_ERROR;
                    end
                end
                ST_COEF_A: begin
                    bram_read(OFF_PAYLOAD + ({24'd0, load_index} << 2));
                    state <= ST_COEF_B;
                end
                ST_COEF_B: begin
                    coef_we    <= 1'b1;
                    coef_addr  <= load_index;
                    coef_wdata <= bram_doutb;
                    if (load_index == TAP_COUNT-1) begin
                        state <= ST_DONE;
                    end else begin
                        load_index <= load_index + 1'b1;
                        state <= ST_COEF_A;
                    end
                end
                ST_DONE: begin
                    coef_generation <= new_generation;
                    coef_ready <= 1'b1;
                    coef_error <= 1'b0;
                    state <= ST_IDLE;
                end
                ST_ERROR: begin
                    coef_error <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
