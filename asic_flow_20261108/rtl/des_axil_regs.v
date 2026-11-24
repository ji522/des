`timescale 1ns / 1ps
// ============================================================================
// des_axil_regs.v —— DES 的 AXI4-Lite 寄存器从机
//
// 寄存器映射（字对齐，addr[5:2] 解码）：
//   0x00 KEY_LO      读写  密钥 [31:0]
//   0x04 KEY_HI      读写  密钥 [63:32]，写入即触发一次密钥加载（load_key_o 单拍）
//   0x08 CTRL        读写  [0] MODE   1=加密 0=解密
//                          [1] ENABLE 数据通路使能
//                          [2] CLR_ERR 写 1 清除 REKEY_ERR（不碰数据通路）
//   0x0C STATUS      只读  [0] KEY_READY  ready_key_i 镜像
//                          [1] BUSY       在途数据非空（来自 wrapper 的在途计数）
//                          [2] KEY_BUSY   已加载过密钥且正在计算子密钥
//                          [3] REKEY_ERR  在途换钥被拒绝（粘滞，CTRL.CLR_ERR 清除）
//   0x10 REKEY_GUARD 读写  [0] 0=拒绝在途换钥（默认） 1=放行
//
// 为什么有 REKEY_GUARD：key_ram 被 key schedule 与流水线共用，在途换钥会让
// 解密路径读到半新半旧的子密钥（工程实测 4/4 错）。原版只在验证环境里强制
// 排空来规避，属使用约束。这里把约束下沉到 RTL：在途时拒绝 load_key_o 并置
// REKEY_ERR，把静默的数据错误变成可观测的状态位。
//
// 设计取舍：单拍传输、无 outstanding、无 burst；WSTRB 逐字节生效；地址越界
// 读返回 0xDEADBEEF 便于 debug（不是总线错误，BRESP/RRESP 恒 OKAY）。
// ============================================================================
module des_axil_regs (
    input  wire        clk,
    input  wire        rst_n,

    // ---- AXI4-Lite slave ----
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,
    input  wire [31:0] s_axil_awaddr,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,
    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    output wire        s_axil_bvalid,
    input  wire        s_axil_bready,
    output wire [1:0]  s_axil_bresp,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,
    input  wire [31:0] s_axil_araddr,
    output wire        s_axil_rvalid,
    input  wire        s_axil_rready,
    output wire [31:0] s_axil_rdata,
    output wire [1:0]  s_axil_rresp,

    // ---- 到 DES 的控制面 ----
    output wire [63:0] key_o,
    output wire        load_key_o,      // 单拍脉冲
    output wire        encrypt_o,
    output wire        des_enable_o,

    // ---- 来自 DES / wrapper 的状态 ----
    input  wire        ready_key_i,
    input  wire        busy_i           // 在途拍数 != 0
);

    localparam [3:0] ADDR_KEY_LO      = 4'h0;
    localparam [3:0] ADDR_KEY_HI      = 4'h1;
    localparam [3:0] ADDR_CTRL        = 4'h2;
    localparam [3:0] ADDR_STATUS      = 4'h3;
    localparam [3:0] ADDR_REKEY_GUARD = 4'h4;

    reg [63:0] key_r;
    reg        encrypt_r;
    reg        enable_r;
    reg        load_key_r;
    reg        key_loaded_r;
    reg        rekey_err_r;
    reg        rekey_guard_r;

    assign key_o        = key_r;
    assign load_key_o   = load_key_r;
    assign encrypt_o    = encrypt_r;
    assign des_enable_o = enable_r;

    // ========================================================================
    // 写通道：AW / W 独立到达，任一方先到都要等另一方
    // ========================================================================
    reg        aw_pend, w_pend;
    reg [3:0]  aw_addr_lat;
    reg [31:0] w_data_lat;
    reg [3:0]  w_strb_lat;
    reg        bvalid_r;

    assign s_axil_awready = !aw_pend;
    assign s_axil_wready  = !w_pend;
    assign s_axil_bvalid  = bvalid_r;
    assign s_axil_bresp   = 2'b00;

    wire aw_fire = s_axil_awvalid && s_axil_awready;
    wire w_fire  = s_axil_wvalid  && s_axil_wready;
    wire do_write = (aw_pend || aw_fire) && (w_pend || w_fire);

    wire [3:0]  wr_addr = aw_pend ? aw_addr_lat : s_axil_awaddr[5:2];
    wire [31:0] wr_data = w_pend  ? w_data_lat  : s_axil_wdata;
    wire [3:0]  wr_strb = w_pend  ? w_strb_lat  : s_axil_wstrb;

    // 在途时拒绝换钥
    wire rekey_blocked = busy_i && !rekey_guard_r;

    integer b;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_pend      <= 1'b0;
            w_pend       <= 1'b0;
            aw_addr_lat  <= 4'h0;
            w_data_lat   <= 32'h0;
            w_strb_lat   <= 4'h0;
            bvalid_r     <= 1'b0;
            key_r        <= 64'h0;
            encrypt_r    <= 1'b1;
            enable_r     <= 1'b0;
            load_key_r   <= 1'b0;
            key_loaded_r <= 1'b0;
            rekey_err_r  <= 1'b0;
            rekey_guard_r<= 1'b0;
        end else begin
            load_key_r <= 1'b0;     // 默认单拍脉冲

            // ---- AW / W 挂起 ----
            if (aw_fire && !(w_pend || w_fire)) begin
                aw_pend     <= 1'b1;
                aw_addr_lat <= s_axil_awaddr[5:2];
            end else if (do_write) begin
                aw_pend     <= 1'b0;
            end

            if (w_fire && !(aw_pend || aw_fire)) begin
                w_pend     <= 1'b1;
                w_data_lat <= s_axil_wdata;
                w_strb_lat <= s_axil_wstrb;
            end else if (do_write) begin
                w_pend     <= 1'b0;
            end

            // ---- B 响应 ----
            if (do_write)                    bvalid_r <= 1'b1;
            else if (bvalid_r && s_axil_bready) bvalid_r <= 1'b0;

            // ---- 执行写 ----
            if (do_write) begin
                case (wr_addr)
                    ADDR_KEY_LO: begin
                        for (b = 0; b < 4; b = b + 1)
                            if (wr_strb[b]) key_r[b*8 +: 8] <= wr_data[b*8 +: 8];
                    end
                    ADDR_KEY_HI: begin
                        for (b = 0; b < 4; b = b + 1)
                            if (wr_strb[b]) key_r[32 + b*8 +: 8] <= wr_data[b*8 +: 8];
                        if (rekey_blocked) begin
                            rekey_err_r <= 1'b1;
                        end else begin
                            load_key_r   <= 1'b1;
                            key_loaded_r <= 1'b1;
                        end
                    end
                    ADDR_CTRL: begin
                        encrypt_r <= wr_data[0];
                        enable_r  <= wr_data[1];
                        if (wr_data[2]) rekey_err_r <= 1'b0;
                    end
                    ADDR_REKEY_GUARD: begin
                        rekey_guard_r <= wr_data[0];
                    end
                    default: ;
                endcase
            end
        end
    end

    // ========================================================================
    // 读通道：AR 握手后拉 RVALID 直到 RREADY
    // ========================================================================
    reg        rvalid_r;
    reg [31:0] rdata_r;

    assign s_axil_arready = !rvalid_r;
    assign s_axil_rvalid  = rvalid_r;
    assign s_axil_rdata   = rdata_r;
    assign s_axil_rresp   = 2'b00;

    wire ar_fire = s_axil_arvalid && s_axil_arready;

    wire [31:0] status_vec = {
        28'h0,
        rekey_err_r,
        (key_loaded_r && !ready_key_i),
        busy_i,
        ready_key_i
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rvalid_r <= 1'b0;
            rdata_r  <= 32'h0;
        end else begin
            if (ar_fire) begin
                case (s_axil_araddr[5:2])
                    ADDR_KEY_LO:      rdata_r <= key_r[31:0];
                    ADDR_KEY_HI:      rdata_r <= key_r[63:32];
                    // CTRL 读回：[0] MODE  [1] ENABLE  [2] 恒 0（CLR_ERR 是 WO）
                    // 位宽必须精确 32：29 + 1(bit2) + 1(bit1) + 1(bit0) = 32
                    ADDR_CTRL:        rdata_r <= {29'h0, 1'b0, enable_r, encrypt_r};
                    ADDR_STATUS:      rdata_r <= status_vec;
                    ADDR_REKEY_GUARD: rdata_r <= {31'h0, rekey_guard_r};
                    default:          rdata_r <= 32'hDEADBEEF;
                endcase
                rvalid_r <= 1'b1;
            end else if (rvalid_r && s_axil_rready) begin
                rvalid_r <= 1'b0;
            end
        end
    end

endmodule
