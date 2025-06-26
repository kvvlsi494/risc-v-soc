`timescale 1ns / 1ps

module risc_soc (
    input clk,
    input rst_n,
    input bfm_mode,
    output uart_tx_pin,
    input uart_rx_pin
);
    wire cpu_m_req, cpu_m_gnt;
    wire [31:0] cpu_m_addr, cpu_m_wdata, cpu_m_rdata;
    wire cpu_m_wr_en;
    wire dma_m_req, dma_m_gnt;
    wire [31:0] dma_m_addr, dma_m_wdata, dma_m_rdata;
    wire dma_m_wr_en;
    wire [31:0] bus_addr, bus_wdata, bus_rdata;
    wire bus_wr_en;
    wire ram_cs_n, dma_s_cs_n, crc_cs_n, intc_cs_n, timer_cs_n, uart_cs_n; // Updated
    wire [31:0] ram_rdata, dma_s_rdata, crc_rdata, intc_rdata, timer_rdata, uart_rdata; // Updated
    wire dma_done_irq, timer_irq_out, uart_irq_out, cpu_irq_in; // Updated

    assign bus_addr = dma_m_gnt ? dma_m_addr : cpu_m_addr;
    assign bus_wr_en = dma_m_gnt ? dma_m_wr_en : cpu_m_wr_en;
    assign bus_wdata = dma_m_gnt ? dma_m_wdata : cpu_m_wdata;

    assign bus_rdata = !ram_cs_n ? ram_rdata :
                       !dma_s_cs_n ? dma_s_rdata :
                       !crc_cs_n ? crc_rdata :
                       !timer_cs_n ? timer_rdata :
                       !intc_cs_n ? intc_rdata :
                       !uart_cs_n ? uart_rdata : // Updated
                       32'hBAD_DDAA;

    assign cpu_m_rdata = bus_rdata;
    assign dma_m_rdata = bus_rdata;

    simple_cpu u_cpu ( .clk(clk), .rst_n(rst_n), .irq_in(cpu_irq_in), .bfm_mode(bfm_mode), .m_req(cpu_m_req), .m_gnt(cpu_m_gnt), .m_addr(cpu_m_addr), .m_wr_en(cpu_m_wr_en), .m_wdata(cpu_m_wdata), .m_rdata(cpu_m_rdata) );
    dma_engine u_dma ( .clk(clk), .rst_n(rst_n), .s_cs_n(dma_s_cs_n), .s_wr_en(bus_wr_en), .s_addr(bus_addr[4:2]), .s_wdata(bus_wdata), .s_rdata(dma_s_rdata), .m_req(dma_m_req), .m_gnt(dma_m_gnt), .m_addr(dma_m_addr), .m_wr_en(dma_m_wr_en), .m_wdata(dma_m_wdata), .m_rdata(dma_m_rdata), .dma_done(dma_done_irq) );
    crc32_accelerator u_crc ( .clk(clk), .rst_n(rst_n), .cs_n(crc_cs_n), .wr_en(bus_wr_en), .addr(bus_addr[3:2]), .wdata(bus_wdata), .rdata(crc_rdata) );
    on_chip_ram u_ram ( .clk(clk), .cs_n(ram_cs_n), .wr_en(bus_wr_en), .addr(bus_addr[15:0]), .wdata(bus_wdata), .rdata(ram_rdata) );
    arbiter u_arbiter ( .clk(clk), .rst_n(rst_n), .req_0(cpu_m_req), .req_1(dma_m_req), .gnt_0(cpu_m_gnt), .gnt_1(dma_m_gnt) );
    timer u_timer ( .clk(clk), .rst_n(rst_n), .cs_n(timer_cs_n), .wr_en(bus_wr_en), .addr(bus_addr[3:0]), .wdata(bus_wdata), .rdata(timer_rdata), .irq_out(timer_irq_out) );
    
    interrupt_controller u_intc ( .clk(clk), .rst_n(rst_n), .irq0_in(dma_done_irq), .irq1_in(timer_irq_out), .irq2_in(uart_irq_out), .cs_n(intc_cs_n), .wr_en(bus_wr_en), .addr(bus_addr[3:0]), .rdata(intc_rdata), .irq_out(cpu_irq_in) );

    address_decoder u_addr_decoder ( .addr(bus_addr), .ram_cs_n(ram_cs_n), .dma_cs_n(dma_s_cs_n), .crc_cs_n(crc_cs_n), .intc_cs_n(intc_cs_n), .timer_cs_n(timer_cs_n), .uart_cs_n(uart_cs_n) );

    // ** NEW: Instantiate the single UART Top module **
    uart_top u_uart (
        .clk (clk),
        .rst_n (rst_n),
        .cs_n (uart_cs_n),
        .wr_en (bus_wr_en),
        .addr (bus_addr[3:0]),
        .wdata (bus_wdata),
        .rdata (uart_rdata),
        .tx_pin (uart_tx_pin),
        .rx_pin (uart_rx_pin),
        .irq_out (uart_irq_out)
    );
endmodule

