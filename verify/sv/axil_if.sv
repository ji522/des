// ============================================================================
// axil_if.sv —— AXI4-Lite 从机验证接口（含协议 SVA）
//
// 与 des_if.sv 分开：des_if 管数据面的 valid/ready，这里管控制面的
// AW/W/B/AR/R 五个通道。两边共用同一个 clk，但各自独立挂断言。
//
// 断言覆盖 AXI4-Lite 的经典坑：
//   L1 VALID 拉高后、握手前不得撤销（五个通道各自一条）
//   L2 握手成功前 payload 不得变化（AWADDR/WDATA/ARADDR）
//   L3 BVALID 必须等 AWVALID 与 WVALID 都到过才允许拉高
//   L4 复位期间所有 VALID 必须为低
// ============================================================================
interface axil_if (input logic clk);

    logic        rst_n;

    logic        awvalid;
    logic        awready;
    logic [31:0] awaddr;
    logic        wvalid;
    logic        wready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        bvalid;
    logic        bready;
    logic [1:0]  bresp;
    logic        arvalid;
    logic        arready;
    logic [31:0] araddr;
    logic        rvalid;
    logic        rready;
    logic [31:0] rdata;
    logic [1:0]  rresp;

    modport DUT (
        input  clk, rst_n,
        input  awvalid, awaddr, wvalid, wdata, wstrb, bready, arvalid, araddr, rready,
        output awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp
    );

    modport DRV (
        input  clk, rst_n, awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp,
        output awvalid, awaddr, wvalid, wdata, wstrb, bready, arvalid, araddr, rready
    );

    modport MON (
        input clk, rst_n, awvalid, awready, awaddr, wvalid, wready, wdata, wstrb,
        bvalid, bready, bresp, arvalid, arready, araddr, rvalid, rready, rdata, rresp
    );

    // ---------------- L1：VALID 不得在握手前撤销 ----------------
    property p_awvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> awvalid;
    endproperty
    a_awvalid_stable : assert property (p_awvalid_stable)
        else $error("[SVA L1] AWVALID 在未握手时被撤销");

    property p_wvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> wvalid;
    endproperty
    a_wvalid_stable : assert property (p_wvalid_stable)
        else $error("[SVA L1] WVALID 在未握手时被撤销");

    property p_bvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (bvalid && !bready) |=> bvalid;
    endproperty
    a_bvalid_stable : assert property (p_bvalid_stable)
        else $error("[SVA L1] BVALID 在未握手时被撤销");

    property p_arvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> arvalid;
    endproperty
    a_arvalid_stable : assert property (p_arvalid_stable)
        else $error("[SVA L1] ARVALID 在未握手时被撤销");

    property p_rvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        (rvalid && !rready) |=> rvalid;
    endproperty
    a_rvalid_stable : assert property (p_rvalid_stable)
        else $error("[SVA L1] RVALID 在未握手时被撤销");

    // ---------------- L2：payload 在握手前必须保持 ----------------
    property p_awaddr_hold;
        @(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> $stable(awaddr);
    endproperty
    a_awaddr_hold : assert property (p_awaddr_hold)
        else $error("[SVA L2] AWADDR 在未握手时变化");

    property p_wdata_hold;
        @(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> ($stable(wdata) && $stable(wstrb));
    endproperty
    a_wdata_hold : assert property (p_wdata_hold)
        else $error("[SVA L2] WDATA/WSTRB 在未握手时变化");

    property p_araddr_hold;
        @(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> $stable(araddr);
    endproperty
    a_araddr_hold : assert property (p_araddr_hold)
        else $error("[SVA L2] ARADDR 在未握手时变化");

    property p_rdata_hold;
        @(posedge clk) disable iff (!rst_n)
        (rvalid && !rready) |=> $stable(rdata);
    endproperty
    a_rdata_hold : assert property (p_rdata_hold)
        else $error("[SVA L2] RDATA 在未握手时变化");

    // ---------------- L3：复位期间 VALID 必须为低 ----------------
    property p_reset_idle;
        @(posedge clk)
        !rst_n |-> (!awvalid && !wvalid && !arvalid);
    endproperty
    a_reset_idle : assert property (p_reset_idle)
        else $error("[SVA L3] 复位期间 VALID 被拉高");

    // ---------------- L4：控制信号无 X ----------------
    property p_ctrl_known;
        @(posedge clk) disable iff (!rst_n)
        !$isunknown({awready, wready, bvalid, arready, rvalid, bresp, rresp});
    endproperty
    a_ctrl_known : assert property (p_ctrl_known)
        else $error("[SVA L4] AXI4-Lite 控制/响应信号出现 X/Z");

endinterface
