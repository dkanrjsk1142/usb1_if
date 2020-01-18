// --------------------------------------------------------
// File Name   : usb_phy.v
// Description : usb phy controller
//               recognize Signal J/K/SE0/SE1 (SE:Single-Ended)
//                   D+   D-
//               J : L    H  (Low Speed) (Full Speed is inverse) idle line state
//               K : H    L  (Low Speed) (Full Speed is inverse) inverse of J
//             SE0 : L    L
//             SE1 : H    H  ***never occur. this is seen as an error
// --------------------------------------------------------
// Ver     Date       Author              Comment
// 0.01    2020.01.18 I.Yang              Create New
// --------------------------------------------------------

`timescale 1ns / 1ps

module usb_phy #(
	parameter SYS_CLK_FREQ = 24000000, // 24MHz
	parameter USB_VER_1_X  =        1, // 1:USB1.1 / 0:USB1.0
	parameter SYNC_MODE      = 8, // 1: async(clk_enqueue_i - clk_dequeue_i is different clk) / 0: sync(same clk)
	parameter BUF_ADDR_WIDTH = 8, // BUF_SIZE = 2^BUF_ADR_WIDTH
	parameter DATA_BIT_WIDTH = 8, // 
	parameter WAIT_DELAY     = 0  // wait reply delay(0:no wait reply from receive module)
) (

	input  wire                      rst_ni,
	input  wire                      clk_i,

	// 
	input  wire                      usb_rx_dp_i, // weak pull-down(not allowed usb spec)
	input  wire                      usb_rx_dm_i, // weak pull-down(not allowed usb spec)

	output wire                      usb_tx_dp_o,
	output wire                      usb_tx_dm_o,
	output wire                      usb_tx_oe_o,

	output wire                      usb_dp_pull_up_en_o, // for emulate low/full speed
	output wire                      usb_dm_pull_up_en_o, // for emulate low/full speed

	input  wire                      usb_disconnect_i, // 1: set bus Hi-Z. 0: when reconnect, set J state after 2us SE0 state

	// 
	output wire                      sync_det_o,

	output wire                      init_ok_o,

	input  wire                      dequeue_wait_i,
	output wire                      dequeue_den_o,
	output wire [DATA_BIT_WIDTH-1:0] dequeue_data_o,
	output wire                      is_queue_empty_o // loosy empty status(there is some delay after queue is empty)
);


localparam [3:0]  USB_CLK_EN_CNTR = (USB_VER_1_X == 1) ? 4'h1, 4'hF;

localparam [1:0]  SE0_STATE     = 2'b00;
localparam [1:0]  J_STATE       = (USB_VER_1_X == 1) ? 2'b10 : 2'b01;
localparam [1:0]  K_STATE       = (USB_VER_1_X == 1) ? 2'b01 : 2'b10;
localparam [1:0]  SE1_STATE     = 2'b11;

localparam [CNT_BITWIDTH-1:0] p_num_clk_cntr_max  = (SYS_CLK_FREQ / BAUD_RATE) - 1;
localparam [CNT_BITWIDTH-1:0] p_num_clk_cntr_half = (SYS_CLK_FREQ / BAUD_RATE) / 2;

reg         s_clk_en;
reg  [ 3:0] s_clk_en_cntr;

reg  [ 1:0] s_usb_rx_dp_d;
reg  [ 1:0] s_usb_rx_dm_d;
reg  [ 1:0] s_rx_data; // 0:SE0, 1:J, 2:K, 3:SE1

reg  [CNT_BITWIDTH-1:0] s_rx_bit_cntr;
reg  [ 3:0] s_rx_word_cntr;
wire        s_rx_fetch_tmg;
reg  [ 7:0] s_rx_data;

reg        s_rx_irq;
reg  [7:0] s_rx_data_1d;

reg  [ 1:0] s_tx_irq_d;
reg  [ 7:0] s_tx_data;
reg  [ 7:0] s_tx_data_1d;
reg         s_tx_en;
reg  [CNT_BITWIDTH-1:0] s_tx_bit_cntr;
reg  [ 3:0] s_tx_word_cntr;
wire        s_tx_fetch_tmg;

// --------------------
// function
// --------------------
// Binary2Graycode converter
function [BUF_ADDR_WIDTH-1:0] bin2gray(input [BUF_ADDR_WIDTH-1:0] binary);
	bin2gray = binary ^ (binary >> 1);
endfunction
// --------------------

// wr address
always @(negedge rst_ni, posedge clk_enqueue_i)
begin
	if(~rst_ni)
		s_enqueue_addr <= {{BUF_ADDR_WIDTH{1'b0}}, 1'b1}; // for make graycode
	else if(clk_enqueue_i) begin
		if (s_enqueue_den_1d)
			s_enqueue_addr <= s_enqueue_addr + 1'b1;
	end
end

// --------------------
// CLK EN
// Low Speed  : 1/16 @ 24MHz
// Full Speed :  1/2 @ 24MHz
// --------------------
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_clk_en_cntr <= 4'b0;
	else if(clk_enqueue_i) begin
		if (s_rx_chg_det) // clk recovery
			s_clk_en_cntr <= 4'b0;
		else
			s_clk_en_cntr <= s_clk_en_cntr + 1'b1;
	end
end


// --------------------
// NRZ-I
// --------------------



// --------------------
// remove bit-stuff
// --------------------

// control external pull-up register
generate if (USB_VER_1_X == 1) begin
	assign usb_dp_pull_up_en_o = 1'b1;
	assign usb_dm_pull_up_en_o = 1'b0;
end else
	assign usb_dp_pull_up_en_o = 1'b0;
	assign usb_dm_pull_up_en_o = 1'b1;
end

// not need bit-stuffing for
// PID***************************************************************************************

// --------------------
// rx
// --------------------
// --------------------
// rx
// --------------------
//
//                   D+   D-
//               J : L    H  (Low Speed) (Full Speed is inverse) idle line state
//               K : H    L  (Low Speed) (Full Speed is inverse) inverse of J
//             SE0 : L    L
//             SE1 : H    H  ***never occur. this is seen as an error

// rx data shift register
always @(negedge rst_ni, posedge clk_i)
begin
    if(~rst_ni) begin
		s_usb_rx_dp_d <= 2'b0;
		s_usb_rx_dm_d <= 2'b0;
		s_rx_chg_det  <= 1'b0;
    end else if(clk_i) begin
		s_usb_rx_dp_d <= {s_usb_rx_dp_d[0], usb_rx_dp_i};
		s_usb_rx_dm_d <= {s_usb_rx_dm_d[0], usb_rx_dm_i};

		if (^s_usb_rx_dp_d | ^s_usb_rx_dm_d) // something change detected
			s_rx_chg_det <= 1'b1;
		else
			s_rx_chg_det <= 1'b0;
    end
end

// received data
// 0:SE0, 1:J, 2:K, 3:SE1
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_data <= 2'b0;
	else if(clk_i) begin
		if(s_clk_en)
			s_rx_data <= {s_usb_rx_dp_d[1], s_usb_rx_dm_d[1]};
	end
end

// receive state(by start bit)
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_en  <= 1'b0;
	else if(clk_i) begin
		if (s_rx_word_cntr == 4'd9 && s_rx_fetch_tmg) // not parity
			s_rx_en  <= 1'b0;
		else if (s_uart_rx_d == 2'b10) // negedge
			s_rx_en  <= 1'b1;
	end
end

// bit counter
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_bit_cntr <= {CNT_BITWIDTH{1'b0}};
	else if(clk_i) begin
		if (~s_rx_en || s_rx_bit_cntr == p_num_clk_cntr_max)
			s_rx_bit_cntr <= {CNT_BITWIDTH{1'b0}};
		else
			//s_rx_bit_cntr <= s_rx_bit_cntr + {{CNT_BITWIDTH-1{1'b0}}, 1'b1};
			s_rx_bit_cntr <= s_rx_bit_cntr + 1'b1;
	end
end

assign s_rx_fetch_tmg = s_rx_bit_cntr == p_num_clk_cntr_half ? 1'b1 : 1'b0;

// word counter
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_word_cntr  <= 4'b0;
	else if(clk_i) begin
		if (~s_rx_en)
			s_rx_word_cntr  <= 4'b0;
		else if(s_rx_fetch_tmg)
				s_rx_word_cntr  <= s_rx_word_cntr + 4'b1;
	end
end

// convert s/p
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_data <= 8'hFF;
	else if(clk_i) begin
		if (s_rx_fetch_tmg && s_rx_word_cntr != 4'd9)
			s_rx_data <= {s_uart_rx_d[1], s_rx_data[7:1]};
	end
end

// rx complete irq
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_irq  <= 1'b0;
	//if(clk_i) begin -- mod Ver0.05
	else if(clk_i) begin
		if (s_rx_word_cntr == 4'd9 && s_rx_fetch_tmg)
			s_rx_irq <= 1'b1;
		else
			s_rx_irq <= 1'b0;
	end
end

// rx data latch
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_data_1d <= 8'b0;
	//if(clk_i) begin -- mod Ver0.05
	else if(clk_i) begin
		if (s_rx_word_cntr == 4'd9 && s_rx_fetch_tmg)
			s_rx_data_1d <= s_rx_data; // latch
	end
end

assign rx_irq_o  = s_rx_irq;
assign rx_data_o = s_rx_data_1d;

// --------------------
// TX
// --------------------

always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni) begin
		s_tx_irq_d   <= 2'b0;
		s_tx_data    <= 8'b0;
		s_tx_data_1d <= 8'b0;
	end else if(clk_i) begin
		s_tx_irq_d <= {s_tx_irq_d[0], tx_irq_i};
		s_tx_data  <= tx_data_i;
		if (s_tx_irq_d == 2'b01) // posedge
			s_tx_data_1d <= s_tx_data;
	end
end

// transmit state(by start bit)
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_tx_en  <= 1'b0;
	else if(clk_i) begin
		//if (s_tx_word_cntr == 4'd10 && s_tx_fetch_tmg) // not parity -- mod Ver0.04
		if (s_tx_word_cntr == 4'd9 && s_tx_fetch_tmg) // not parity
			s_tx_en  <= 1'b0;
		else if (s_tx_irq_d == 2'b01) // posedge
			s_tx_en  <= 1'b1;
	end
end

// bit counter
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_tx_bit_cntr <= {CNT_BITWIDTH{1'b0}};
	else if(clk_i) begin
		if (~s_tx_en || s_tx_bit_cntr == p_num_clk_cntr_max)
			s_tx_bit_cntr <= {CNT_BITWIDTH{1'b0}};
		else
			//s_tx_bit_cntr <= s_tx_bit_cntr + {{(CNT_BITWIDTH-1){1'b0}}, 1'b1};
			s_tx_bit_cntr <= s_tx_bit_cntr + 1'b1;
	end
end

assign s_tx_fetch_tmg = s_tx_bit_cntr == p_num_clk_cntr_max ? 1'b1 : 1'b0; // not delay but !=0

// word counter
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_tx_word_cntr  <= 4'b0;
	else if(clk_i) begin
		if (~s_tx_en)
			s_tx_word_cntr  <= 4'b0;
		else if(s_tx_fetch_tmg)
				s_tx_word_cntr  <= s_tx_word_cntr + 4'b1;
	end
end

// convert p/s
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		uart_tx_o <= 1'b1;
	else if(clk_i) begin
		case (s_tx_word_cntr)
			4'h1 : uart_tx_o <= 1'b0; // start bit
			4'h2 , 4'h3 , 4'h4 , 4'h5 , 
			4'h6 , 4'h7 , 4'h8 , 4'h9 : 
				   uart_tx_o <= s_tx_data_1d[s_tx_word_cntr-2];
			4'hA : uart_tx_o <= 1'b1; // stop bit
			default : uart_tx_o <= 1'b1;
		endcase
	end
end

assign tx_busy_o = s_tx_en;

endmodule
// --------------------
