// --------------------------------------------------------
// File Name   : TB_USB1_IF_TOP.v
// Description : Bench TOP USB1_IF
// --------------------------------------------------------
// Ver     Date       Author              Comment
// 0.01    2020.01.28 I.Yang              Create New(draft)
//                                        usb_phy.v only
// --------------------------------------------------------



`timescale 1ns / 1ps

module TB_USB1_IF_TOP;


// --------------------
// CLK/RST
// --------------------
reg  s_clk_en;
wire s_clk_24m;
wire s_clk_115k;
wire s_rsth;

initial begin
	s_clk_en = 1'b0;
	#100
	s_clk_en = 1'b1;
end

tb_clk #(24000000, 50) u_tb_clk_24m  (s_clk_en, s_clk_24m , s_rsth);

// --------------------
// usb_phy only
// --------------------
reg  s_sim_en_usb_phy;

initial begin
	s_sim_en_usb_phy = 1'b0; // set by force
end

tb_usb_phy#(
	.USB_VER_1_X (1               )
) u_tb_usb_phy (
	.rst_ni      (~s_rsth         ),
	.clk_i       (s_clk_24m       ),
    .sim_en_i    (s_sim_en_usb_phy)
);

// --------------------
// RTL
// --------------------
//T.B.D.

endmodule
