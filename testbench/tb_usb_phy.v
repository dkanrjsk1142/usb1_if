// --------------------------------------------------------
// File Name   : usb_phy.v
// Description : usb phy controller
//               control bus
//               recognize(rx)/generate(tx) Signal J/K/SE0/SE1 (SE:Single-Ended)
//                        D+   D-
//                    J : L    H  (Low Speed) (Full Speed is inverse) idle line state
//                    K : H    L  (Low Speed) (Full Speed is inverse) inverse of J
//                  SE0 : L    L
//                  SE1 : H    H  ***never occur. this is seen as an error
//
//               RX - detect sync/eop, convert signal to bit-stream and remove bit-stuff
//               TX - attach sync/eop and bit-stuffing
// --------------------------------------------------------
// Ver     Date       Author              Comment
// 0.01    2020.01.xx I.Yang              Create New
// --------------------------------------------------------

`timescale 1ns / 1ps

module tb_usb_phy #(
	parameter USB_VER_1_X  = 1  // 1:USB1.1 / 0:USB1.0
) (
	input  wire                      rst_ni,
	input  wire                      clk_i,        // 24MHz

	input  wire                      sim_en_i
);

wire        usb_dp;
wire        usb_dm;

reg  [30:0] s_data;
reg         s_den;

reg         s_sim_en_1d;
reg  [ 4:0] s_sim_en_cntr;

always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni) begin
		s_sim_en_1d <= 1'b0;
		s_sim_en_cntr <= 5'b0;
	end else if (clk_i) begin
		s_sim_en_1d <= sim_en_i;
		if(sim_en_i & ~s_sim_en_1d) // posedge
			s_sim_en_cntr <= 5'b1;
		else if(|s_sim_en_cntr)
			s_sim_en_cntr <= s_sim_en_cntr + 1'b1;
		else
			s_sim_en_cntr <= 5'b0;
	end
end

always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni) begin
		s_den  <= 1'b0;
		s_data <= 31'b1011010101111111010101101010101; // include need-bit-stuff pattern
	end else if (clk_i) begin
		if(|s_sim_en_cntr) begin // posedge
			s_den  <= 1'b1;
			s_data <= {s_data[29:0], s_data[30]};
		end else begin
			s_den  <= 1'b0;
			s_data <= 31'b1011010101111111010101101010101; // include need-bit-stuff pattern
		end
	end
end

usb_phy #(
	.USB_VER_1_X         (1                          )  // 1:USB1.1 / 0:USB1.0 // parameter USB_VER_1_X  = 1  // 1:USB1.1 / 0:USB1.0
) u_tx_usb_phy (
	.rst_ni              (rst_ni                     ),	// input  wire                      rst_ni,
	.clk_i               (clk_i                      ),	// input  wire                      clk_i,        // 24MHz

	// // phy - bus control
	.usb_tx_oe_o         (                           ),	// output wire                      usb_tx_oe_o, // 1: tx / 0: rx(hi-z)

	.usb_dp_pull_up_en_o (                           ),	// output wire                      usb_dp_pull_up_en_o, // connect external pull-up resistor switch
	.usb_dm_pull_up_en_o (                           ),	// output wire                      usb_dm_pull_up_en_o, // connect external pull-up resistor switch

	// // phy - rx
	.usb_rx_dp_i         (usb_dp                     ),	// input  wire                      usb_rx_dp_i, // weak pull-down(not allowed usb spec)
	.usb_rx_dm_i         (usb_dm                     ),	// input  wire                      usb_rx_dm_i, // weak pull-down(not allowed usb spec)

	// // phy - tx
	.usb_tx_dp_o         (usb_dp                     ),	// output wire                      usb_tx_dp_o,
	.usb_tx_dm_o         (usb_dm                     ),	// output wire                      usb_tx_dm_o,

	// // logic - rx
	.rx_data_o           (                           ),	// output wire                      rx_data_o, // 
	.rx_den_o            (                           ),	// output wire                      rx_den_o,  // 

	.rx_packet_st_o      (                           ),	// output wire                      rx_packet_st_o, // 1clk pulse after SYNC-detected
	.rx_packet_ed_o      (                           ),	// output wire                      rx_packet_ed_o, // 1clk pulse after EOP-detected

	.rx_se0_det_o        (                           ),	// output wire                      rx_se0_det_o, // 1 : d+/d- both 0
	.rx_se1_det_o        (                           ),	// output wire                      rx_se1_det_o, // 1 : d+/d- both 1(error)

	// // logic - tx
	.tx_data_i           (s_data[0]                  ),	// input  wire                      tx_data_i, // data stream without sync/eop
	.tx_den_i            (s_den                      ),	// input  wire                      tx_den_i,  // 1clk pulse when idle state. keep TX(line status) until EOP.
	.tx_busy_o           (                           )	// output wire                      tx_busy_o  // 1:ignore tx_den/data
);

usb_phy #(
	.USB_VER_1_X         (1                          )  // 1:USB1.1 / 0:USB1.0 // parameter USB_VER_1_X  = 1  // 1:USB1.1 / 0:USB1.0
) u_rx_usb_phy (
    .rst_ni              (rst_ni                     ),	// input  wire                      rst_ni,
    .clk_i               (clk_i                      ),	// input  wire                      clk_i,        // 24MHz

    // // phy - bus control
    .usb_tx_oe_o         (                           ),	// output wire                      usb_tx_oe_o, // 1: tx / 0: rx(hi-z)

    .usb_dp_pull_up_en_o (                           ),	// output wire                      usb_dp_pull_up_en_o, // connect external pull-up resistor switch
    .usb_dm_pull_up_en_o (                           ),	// output wire                      usb_dm_pull_up_en_o, // connect external pull-up resistor switch

    // // phy - rx
    .usb_rx_dp_i         (usb_dp                     ),	// input  wire                      usb_rx_dp_i, // weak pull-down(not allowed usb spec)
    .usb_rx_dm_i         (usb_dm                     ),	// input  wire                      usb_rx_dm_i, // weak pull-down(not allowed usb spec)

    // // phy - tx
    .usb_tx_dp_o         (                           ),	// output wire                      usb_tx_dp_o,
    .usb_tx_dm_o         (                           ),	// output wire                      usb_tx_dm_o,

    // // logic - rx
    .rx_data_o           (                           ),	// output wire                      rx_data_o, // 
    .rx_den_o            (                           ),	// output wire                      rx_den_o,  // 

    .rx_packet_st_o      (                           ),	// output wire                      rx_packet_st_o, // 1clk pulse after SYNC-detected
    .rx_packet_ed_o      (                           ),	// output wire                      rx_packet_ed_o, // 1clk pulse after EOP-detected

    .rx_se0_det_o        (                           ),	// output wire                      rx_se0_det_o, // 1 : d+/d- both 0
    .rx_se1_det_o        (                           ),	// output wire                      rx_se1_det_o, // 1 : d+/d- both 1(error)

    // // logic - tx
    .tx_data_i           (1'b0                       ),	// input  wire                      tx_data_i, // data stream without sync/eop
    .tx_den_i            (1'b0                       ),	// input  wire                      tx_den_i,  // 1clk pulse when idle state. keep TX(line status) until EOP.
    .tx_busy_o           (                           )	// output wire                      tx_busy_o  // 1:ignore tx_den/data
);


endmodule
// --------------------
