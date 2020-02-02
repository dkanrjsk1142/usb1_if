// --------------------------------------------------------
// File Name   : tb_clk.v
// Description : clk / rst(Active H) generator for testbench
// --------------------------------------------------------
// Ver     Date       Author              Comment
// 0.01    2020.01.02 I.Yang              Create New
// --------------------------------------------------------

`timescale 1ns / 1ps

module tb_clk #(
	parameter P_FREQUENCY = 50000000,   // output clk frequency
	parameter P_RST_RELEASE_DLY_US = 50 // reset releasing delay(ms)
) (
	input  wire en,
	output wire clk_o,
	output wire rsth_o
);

reg s_clk;
reg s_rst;
reg s_en_d;

initial s_en_d <= 1'b0;
always #1 s_en_d = en;

always @(posedge s_en_d) begin
	s_clk = 0;
	s_rst = 1;
	#(P_RST_RELEASE_DLY_US * 1000);
	s_rst = 0;
end

always begin
	#(1000 * 1000 * 1000 / P_FREQUENCY / 2) // ns -> s (10**9)
	if (s_en_d) begin
		s_clk = ~s_clk;
	end
end

assign clk_o  = s_clk;
assign rsth_o = s_rst;


endmodule
