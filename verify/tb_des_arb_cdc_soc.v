`timescale 1ns / 1ps
// ============================================================================
// tb_des_arb_cdc_soc.v —— 多时钟 2 通道安全加密前端自检
//
// 三个时钟：
//   wclk0 = 100MHz（10ns），wclk1 ≈ 142.8MHz（7ns），clk = 250MHz（4ns）
// 复位分别异步释放，检验每域 reset_sync。
//
// 流程：
//   ch0(wclk0) 发 ins[0..3]，ch1(wclk1) 发 ins[4..7]
//   -> 异步 FIFO -> 2 通道仲裁 -> DES -> m_axis
// 期望：exps[0..7] 顺序一致，TLAST 在第 4/8 拍；输出带周期反压。
// 通过标志：DES ARB CDC PASS
// ============================================================================
module tb_des_arb_cdc_soc;

    reg         wclk0, wclk1, clk;
    reg         wrst0_n, wrst1_n, rst_n;

    // ch0 (wclk0)
    reg         s0_tvalid;
    wire        s0_tready;
    reg  [63:0] s0_tdata;
    reg         s0_tlast;

    // ch1 (wclk1)
    reg         s1_tvalid;
    wire        s1_tready;
    reg  [63:0] s1_tdata;
    reg         s1_tlast;

    // output (clk)
    wire        m_tvalid;
    reg         m_tready;
    wire [63:0] m_tdata;
    wire        m_tlast;

    // single AXI-Lite (clk)
    reg         axil_awvalid;
    wire        axil_awready;
    reg  [31:0] axil_awaddr;
    reg         axil_wvalid;
    wire        axil_wready;
    reg  [31:0] axil_wdata;
    reg  [3:0]  axil_wstrb;
    wire        axil_bvalid;
    reg         axil_bready;
    wire [1:0]  axil_bresp;
    reg         axil_arvalid;
    wire        axil_arready;
    reg  [31:0] axil_araddr;
    reg         axil_rready;
    wire        axil_rvalid;
    wire [31:0] axil_rdata;
    wire [1:0]  axil_rresp;

    wire        irq;
    wire        arb_busy;
    wire        ready_key;
    wire        fifo0_full, fifo0_empty;
    wire        fifo1_full, fifo1_empty;

    // vectors
    reg [63:0] keys [0:31];
    reg [63:0] ins  [0:31];
    reg [63:0] exps [0:31];

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    des_arb_cdc_top dut (
        .wclk0            (wclk0),
        .wrst0_n          (wrst0_n),
        .s0_axis_tvalid   (s0_tvalid),
        .s0_axis_tready   (s0_tready),
        .s0_axis_tdata    (s0_tdata),
        .s0_axis_tlast    (s0_tlast),

        .wclk1            (wclk1),
        .wrst1_n          (wrst1_n),
        .s1_axis_tvalid   (s1_tvalid),
        .s1_axis_tready   (s1_tready),
        .s1_axis_tdata    (s1_tdata),
        .s1_axis_tlast    (s1_tlast),

        .clk              (clk),
        .rst_n            (rst_n),
        .m_axis_tvalid    (m_tvalid),
        .m_axis_tready    (m_tready),
        .m_axis_tdata     (m_tdata),
        .m_axis_tlast     (m_tlast),

        .s_axil_awvalid   (axil_awvalid),
        .s_axil_awready   (axil_awready),
        .s_axil_awaddr    (axil_awaddr),
        .s_axil_wvalid    (axil_wvalid),
        .s_axil_wready    (axil_wready),
        .s_axil_wdata     (axil_wdata),
        .s_axil_wstrb     (axil_wstrb),
        .s_axil_bvalid    (axil_bvalid),
        .s_axil_bready    (axil_bready),
        .s_axil_bresp     (axil_bresp),
        .s_axil_arvalid   (axil_arvalid),
        .s_axil_arready   (axil_arready),
        .s_axil_araddr    (axil_araddr),
        .s_axil_rready    (axil_rready),
        .s_axil_rvalid    (axil_rvalid),
        .s_axil_rdata     (axil_rdata),
        .s_axil_rresp     (axil_rresp),

        .irq_o            (irq),
        .arb_busy_o       (arb_busy),
        .ready_key_o      (ready_key),
        .fifo0_full       (fifo0_full),
        .fifo0_empty      (fifo0_empty),
        .fifo1_full       (fifo1_full),
        .fifo1_empty      (fifo1_empty)
    );

    // ------------------------------------------------------------------
    // clocks / resets
    // ------------------------------------------------------------------
    initial wclk0 = 1'b0;
    always #5.0 wclk0 = ~wclk0;       // 100 MHz

    initial wclk1 = 1'b0;
    always #3.5 wclk1 = ~wclk1;       // ~142.8 MHz

    initial clk = 1'b0;
    always #2.0 clk = ~clk;           // 250 MHz

    initial begin
        wrst0_n = 1'b0;
        wrst1_n = 1'b0;
        rst_n   = 1'b0;
        #50  wrst0_n = 1'b1;
        #15  wrst1_n = 1'b1;
        #15  rst_n   = 1'b1;
    end

    // output backpressure: every 5th clk deassert
    reg     m_ready_en;
    integer bp_cnt;
    reg     m_tready_r;
    assign  m_tready = m_tready_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            bp_cnt     <= 0;
            m_tready_r <= 1'b0;
        end else if (!m_ready_en) begin
            bp_cnt     <= 0;
            m_tready_r <= 1'b0;
        end else begin
            bp_cnt     <= bp_cnt + 1;
            m_tready_r <= ((bp_cnt % 5) != 0);
        end
    end

    task release_output;
        begin
            @(negedge clk);
            m_ready_en = 1'b1;
        end
    endtask

    // ------------------------------------------------------------------
    // AXI4-Lite helpers (clk)
    // ------------------------------------------------------------------
    task axil_write;
        input [15:0] addr;
        input [31:0] data;
        integer aw_done, w_done;
        begin
            @(posedge clk);
            axil_awvalid <= 1'b1; axil_awaddr <= {16'h0, addr};
            axil_wvalid  <= 1'b1; axil_wdata  <= data; axil_wstrb <= 4'hF;
            aw_done = 0; w_done = 0;
            while (!(aw_done && w_done)) begin
                @(posedge clk);
                if (!aw_done && axil_awvalid && axil_awready) begin
                    axil_awvalid <= 1'b0; aw_done = 1;
                end
                if (!w_done && axil_wvalid && axil_wready) begin
                    axil_wvalid <= 1'b0; w_done = 1;
                end
            end
            while (!axil_bvalid) @(posedge clk);
            axil_bready <= 1'b1;
            @(posedge clk);
            axil_bready <= 1'b0;
        end
    endtask

    task axil_read;
        input  [15:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            axil_arvalid <= 1'b1; axil_araddr <= {16'h0, addr};
            @(posedge clk);
            while (!axil_arready) @(posedge clk);
            axil_arvalid <= 1'b0;
            while (!axil_rvalid) @(posedge clk);
            data = axil_rdata;
            axil_rready <= 1'b1;
            @(posedge clk);
            axil_rready <= 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    // channel drivers (own write clocks)
    // ------------------------------------------------------------------
    task send0_w;
        input integer len;
        input integer base;
        integer k;
        begin
            for (k = 0; k < len; k = k + 1) begin
                @(posedge wclk0);
                s0_tvalid <= 1'b1;
                s0_tdata  <= ins[base + k];
                s0_tlast  <= (k == len-1);
                @(posedge wclk0);
                while (!s0_tready) @(posedge wclk0);
                s0_tvalid <= 1'b0;
                s0_tlast  <= 1'b0;
            end
            s0_tvalid <= 1'b0;
            s0_tlast  <= 1'b0;
        end
    endtask

    task send1_w;
        input integer len;
        input integer base;
        integer k;
        begin
            for (k = 0; k < len; k = k + 1) begin
                @(posedge wclk1);
                s1_tvalid <= 1'b1;
                s1_tdata  <= ins[base + k];
                s1_tlast  <= (k == len-1);
                @(posedge wclk1);
                while (!s1_tready) @(posedge wclk1);
                s1_tvalid <= 1'b0;
                s1_tlast  <= 1'b0;
            end
            s1_tvalid <= 1'b0;
            s1_tlast  <= 1'b0;
        end
    endtask

    // ------------------------------------------------------------------
    // output checker (clk)
    // ------------------------------------------------------------------
    integer out_cnt;
    integer err;
    reg     pwr_mode;

    initial pwr_mode = $test$plusargs("PWR_MODE");

    always @(posedge clk) begin
        if (rst_n && m_tvalid && m_tready) begin
            if (pwr_mode) begin
                // 长流量功耗模式：只查 TLAST 每 4 拍一次，不做 DES 数据对拍
                if (m_tlast !== ((out_cnt % 4) == 3)) begin
                    err = err + 1;
                    $display("[%0t] ERROR pwr out[%0d] tlast=%b", $time, out_cnt, m_tlast);
                end
            end else if (out_cnt < 8) begin
                if (m_tdata !== exps[out_cnt]) begin
                    err = err + 1;
                    $display("[%0t] ERROR out[%0d]=%h exp=%h", $time, out_cnt, m_tdata, exps[out_cnt]);
                end
                if (m_tlast !== ((out_cnt == 3) || (out_cnt == 7))) begin
                    err = err + 1;
                    $display("[%0t] ERROR out[%0d] tlast=%b", $time, out_cnt, m_tlast);
                end
            end else begin
                err = err + 1;
                $display("[%0t] ERROR extra beat %h", $time, m_tdata);
            end
            out_cnt = out_cnt + 1;
        end
    end

    // ------------------------------------------------------------------
    // main
    // ------------------------------------------------------------------
    reg [31:0] rd;
    integer i;
    integer p0, p1;

    initial begin
        s0_tvalid = 1'b0; s0_tdata = 64'h0; s0_tlast = 1'b0;
        s1_tvalid = 1'b0; s1_tdata = 64'h0; s1_tlast = 1'b0;
        m_ready_en = 1'b0;

        axil_awvalid = 1'b0; axil_awaddr = 32'h0;
        axil_wvalid  = 1'b0; axil_wdata  = 32'h0; axil_wstrb = 4'h0;
        axil_bready  = 1'b0;
        axil_arvalid = 1'b0; axil_araddr = 32'h0; axil_rready = 1'b0;

        out_cnt = 0;
        err     = 0;

        $readmemh("keys.mem", keys);
        $readmemh("ins.mem",  ins);
        $readmemh("exps.mem", exps);

        wait (rst_n === 1'b1);
        #100;

        // DES: key + mode + enable (0x000/0x004/0x008)
        axil_write(16'h0000, keys[0][31:0]);
        axil_write(16'h0004, keys[0][63:32]);
        wait (ready_key === 1'b1);
        axil_write(16'h0008, 32'h0000_0003);

        // arbiter enable + threshold (0x100/0x10C)
        axil_write(16'h0100, 32'h0000_0001);
        axil_write(16'h010C, 32'h0000_0008);

        // ---- 长流量功耗模式：32 包/通道，共 256 beat ----
        if (pwr_mode) begin
            fork
                begin
                    for (p0 = 0; p0 < 32; p0 = p0 + 1)
                        send0_w(4, 0);
                end
                begin
                    for (p1 = 0; p1 < 32; p1 = p1 + 1)
                        send1_w(4, 4);
                end
                begin
                    #200;
                    release_output();
                end
            join
            wait (out_cnt == 256);
            #500;
            if (err == 0)
                $display("DES ARB CDC PWR PASS : 256 beats, 64 packets, 3 clocks");
            else
                $display("DES ARB CDC PWR FAIL : err=%0d", err);
            $finish;
        end

        // keep output held while filling both async FIFOs
        send0_w(4, 0);
        #100;
        send1_w(4, 4);
        release_output();

        wait (out_cnt == 8);
        #500;

        axil_read(16'h011C, rd);
        if (rd !== 32'd1) begin err = err + 1; $display("ERROR ch0 pkts_out=%0d", rd); end
        axil_read(16'h0134, rd);
        if (rd !== 32'd1) begin err = err + 1; $display("ERROR ch1 pkts_out=%0d", rd); end
        axil_read(16'h0118, rd);
        if (rd !== 32'd4) begin err = err + 1; $display("ERROR ch0 beats_out=%0d", rd); end
        axil_read(16'h0130, rd);
        if (rd !== 32'd4) begin err = err + 1; $display("ERROR ch1 beats_out=%0d", rd); end

        #200;
        if (err == 0)
            $display("DES ARB CDC PASS : 8 beats, 2 packets, TLAST aligned, 3 clocks");
        else
            $display("DES ARB CDC FAIL : err=%0d", err);
        $finish;
    end

    initial begin
        #1000000;
        $display("DES ARB CDC FAIL : TIMEOUT");
        $finish;
    end

    // 可选 VCD dump（低功耗 SAIF 流程用）：+DUMP_VCD
    initial begin
        if ($test$plusargs("DUMP_VCD")) begin
            $dumpfile("tb_des_arb_cdc_soc.vcd");
            $dumpvars(0, tb_des_arb_cdc_soc.dut);
            $dumpoff;
            wait (rst_n === 1'b1);
            #200;
            $dumpon;
            if (pwr_mode) #8000;
            else          #3000;
            $dumpoff;
        end
    end

endmodule
