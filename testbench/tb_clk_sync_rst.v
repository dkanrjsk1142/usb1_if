// --------------------------------------------------------
// File Name   : tb_clk_sync_rst.v
// Description : clk / rst(Active H) generator for testbench
// --------------------------------------------------------
// Ver     Date       Author              Comment
// 0.01    2020.01.02 I.Yang              Create New
// --------------------------------------------------------

`timescale 1ns / 1ps

module tb_clk_sync_rst #(
	parameter P_FREQUENCY = 50000000,     // output clk frequency
	parameter P_NUM_CLK_RST_RELEASE = 100 // number of clk until reset release
) (
	input  wire en,
	output wire clk_o,
	output wire rsth_o
);

reg s_clk;
reg s_rst;
reg s_en_d;

integer s_rst_dly_cnt;

initial s_en_d <= 1'b0;
always s_en_d <= #1 en;

// always @(posedge s_en_d) begin
// 	s_clk = 0;
// 	s_rst = 1;
// 	#(P_RST_RELEASE_DLY_US * 1000);
// 	s_rst = 0;
// end
initial s_clk = 1'b0;

initial s_rst_dly_cnt = 0;

always @(posedge s_en_d, posedge s_clk) begin
	if (~s_en_d) begin
		s_rst_dly_cnt <= 0;
		s_rst <= 1'b1;
	end else if (s_clk) begin
		if (s_rst_dly_cnt < P_NUM_CLK_RST_RELEASE)
			s_rst_dly_cnt <= s_rst_dly_cnt + 1;
		else
			s_rst <= 1'b0;
	end
end

always begin
	if (s_en_d) begin
		#(1000 * 1000 * 1000 / P_FREQUENCY / 2) // ns -> s (10**9)
		s_clk = ~s_clk;
	end
end

assign clk_o  = s_clk;
assign rsth_o = s_rst;


endmodule
