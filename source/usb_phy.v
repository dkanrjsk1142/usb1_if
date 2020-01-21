// --------------------------------------------------------
// File Name   : usb_phy.v
// Description : usb phy controller
//               recognize(rx)/generate(tx) Signal J/K/SE0/SE1 (SE:Single-Ended)
//                   D+   D-
//               J : L    H  (Low Speed) (Full Speed is inverse) idle line state
//               K : H    L  (Low Speed) (Full Speed is inverse) inverse of J
//             SE0 : L    L
//             SE1 : H    H  ***never occur. this is seen as an error
// --------------------------------------------------------
// Ver     Date       Author              Comment
// 0.01    2020.01.xx I.Yang              Create New
// --------------------------------------------------------

`timescale 1ns / 1ps

module usb_phy #(
	parameter USB_VER_1_X  = 1  // 1:USB1.1 / 0:USB1.0
) (
	input  wire                      rst_ni,
	input  wire                      clk_i,        // 24MHz

	// for physical line
	input  wire                      usb_rx_dp_i, // weak pull-down(not allowed usb spec)
	input  wire                      usb_rx_dm_i, // weak pull-down(not allowed usb spec)

	output wire                      usb_tx_dp_o,
	output wire                      usb_tx_dm_o,
	output wire                      usb_tx_oe_o,

	output wire                      usb_dp_pull_up_en_o, // connect external pull-up resistor switch
	output wire                      usb_dm_pull_up_en_o, // connect external pull-up resistor switch

	input  wire                      usb_disconnect_i, // 1: set bus Hi-Z. 0: when reconnect, set J state after 2us SE0 state

	// for internal RTL
	output wire                      rx_packet_st_o, // 1clk pulse after SYNC-detected
	output wire                      rx_packet_ed_o, // 1clk pulse after EOP-detected

	output wire                      rx_data_o, // 
	output wire                      rx_den_o,  // 

	output wire                      rx_pid_error_o, // 1clk pulse after (pid(MSB4bit) != ~pid(LSB4bit))


	input  wire                      tx_request_i  // 1clk pulse when idle state. keep TX(line status) until EOP.
);


localparam [3:0]  USB_CLK_EN_CNTR = (USB_VER_1_X == 1) ? 4'h1, 4'hF;

localparam [1:0]  SE0_STATE      = 2'b00;
localparam [1:0]  J_STATE        = (USB_VER_1_X == 1) ? 2'b10 : 2'b01;
localparam [1:0]  K_STATE        = (USB_VER_1_X == 1) ? 2'b01 : 2'b10;
localparam [1:0]  SE1_STATE      = 2'b11;

localparam [3:0]  FSM_IDLE       = 4'h0; // SE0 >= 2us
localparam [3:0]  FSM_SYNC       = 4'h1; // check KJKJKJKK (with wdt, goto UNKNOWN after timeout)
localparam [3:0]  FSM_PID        = 4'h2; // check PID(goto UNKNOWN if 0000 or (MSB4bit == ~LSB4bit))
localparam [3:0]  FSM_PAYLOAD    = 4'h3; // SE0 + SE0 + J
localparam [3:0]  FSM_CRC        = 4'h4; // SE0 + SE0 + J
localparam [3:0]  FSM_EOP        = 4'h5; // SE0 + SE0 + J
localparam [3:0]  FSM_RESET      = 4'h3; // SE0 >= 2.5ms
localparam [3:0]  FSM_SUSPEND    = 4'h4; // J >= 3ms -- not use??
localparam [3:0]  FSM_RESUME_HST = 4'h5; // K >= 20ms then EOP pattern
localparam [3:0]  FSM_RESUME_DEV = 4'h6; // after idle > 5ms, K >= 1ms(host replay FSM_RESUME_HST)
localparam [3:0]  FSM_UNKNOWN    = 4'hF; // goto IDLE(which condition?)

localparam [1:0]  PACKET_SOF     = 2'h0;
localparam [1:0]  PACKET_TOKEN   = 2'h1;
localparam [1:0]  PACKET_DATA    = 2'h2;
localparam [1:0]  PACKET_HNDSHK  = 2'h3;
// PACKET_SPLIT(USB2.0 only) is T.B.D.(when support USB2.0)

 
localparam [CNT_BITWIDTH-1:0] p_num_clk_cntr_max  = (SYS_CLK_FREQ / BAUD_RATE) - 1;
localparam [CNT_BITWIDTH-1:0] p_num_clk_cntr_half = (SYS_CLK_FREQ / BAUD_RATE) / 2;

localparam P_RX_CLK_EN_CNTR_WIDTH = (USB_VER_1_X == 1) ? 1 : 4;

reg         s_rx_clk_en;
reg  [P_RX_CLK_EN_CNTR_WIDTH-1:0] s_rx_clk_en_cntr;

reg  [ 1:0] s_usb_rx_dp_d;
reg  [ 1:0] s_usb_rx_dm_d;
reg  [ 1:0] s_rx_data; // 0:SE0, 1:J, 2:K, 3:SE1
wire        s_rx_chg_det;


reg  [2*8-1:0] s_s_rx_symbol_window;
wire           s_sync_det;
wire           s_eop_det;

// --------------------
// BUS control
// --------------------
assign usb_tx_oe_o = s_tx_en;

// External(out of FPGA) resistor switch
generate if (USB_VER_1_X == 1) begin
	assign usb_dp_pull_up_en_o = 1'b1;
	assign usb_dm_pull_up_en_o = 1'b0;
end else
	assign usb_dp_pull_up_en_o = 1'b0;
	assign usb_dm_pull_up_en_o = 1'b1;
end

// --------------------
// RX - generate CLK EN(Data EN)
// --------------------
// CLK EN
assign s_rx_clk_en = (s_rx_clk_en_cntr == {P_RX_CLK_EN_CNTR_WIDTH{1'b0}}) ? 1'b1 : 1'b0;

// CLK EN counter
// Low Speed  : 1/16 @ 24MHz
// Full Speed :  1/2 @ 24MHz
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_clk_en_cntr <= {P_RX_CLK_EN_CNTR_WIDTH{1'b0};
	else if(clk_i) begin
		if (s_rx_chg_det) // clk recovery
			s_rx_clk_en_cntr <= {P_RX_CLK_EN_CNTR_WIDTH{1'b0};
		else
			s_rx_clk_en_cntr <= s_rx_clk_en_cntr + 1'b1;
	end
end

// --------------------
// RX - receive data
// --------------------
// rx data shift register
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni) begin
		s_usb_rx_dp_d <= {2{J_STATE[1]}};
		s_usb_rx_dm_d <= {2{J_STATE[0]}};
	end else if(clk_i) begin
		s_usb_rx_dp_d <= {s_usb_rx_dp_d[0], usb_rx_dp_i};
		s_usb_rx_dm_d <= {s_usb_rx_dm_d[0], usb_rx_dm_i};
	end
end

// something change detected
assign s_rx_chg_det = (^s_usb_rx_dp_d | ^s_usb_rx_dm_d) ? 1'b1 : 1'b0;


// received data
// 0:SE0, 1:J, 2:K, 3:SE1
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_data <= J_STATE;
	else if(clk_i) begin
		if(s_rx_clk_en)
			s_rx_data <= {s_usb_rx_dp_d[1], s_usb_rx_dm_d[1]};
	end
end

// synbol Window
// SYNC : ignore MSB 2bit. because of synchronization loss.
// EOP  : full decode
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_s_rx_symbol_window <= {8{J_STATE}};
	else if(clk_i) begin
		if(s_rx_clk_en)
			s_s_rx_symbol_window <= {s_s_rx_symbol_window, s_rx_data};
	end
end

assign s_sync_det = (s_s_rx_symbol_window == {3{K_STATE, J_STATE}, K_STATE, K_STATE}) ? 1'b1 : 1'b0;
assign s_eop_det  = (s_s_rx_symbol_window[3*2-1:0] == {SE0_STATE, SE0_STATE, J_STATE}) ? 1'b1 : 1'b0;

// need delay???
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni) begin
		s_sync_det_1d <= 1'b0;
		s_eop_det_1d  <= 1'b0;
	end else if(clk_i) begin
		if(s_rx_clk_en) begin
			s_sync_det_1d <= s_sync_det;
			s_eop_det_1d  <= s_eop_det;
		end
	end
end

assign rx_packet_st_o = s_sync_det_1d;
assign rx_packet_ed_o = s_eop_det_1d;

// --------------------
// RX - decode NRZ-I & remove bit-stuff
// --------------------
// bit windows for decode NRZ-I(6bits)
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_bit_window <= 6'b0;
	else if(clk_i) begin
		if(s_rx_clk_en)
			s_rx_bit_window <= {s_rx_bit_window[5:0], ~s_rx_chg_det};
//			if(s_rx_chg_det)
//				s_rx_bit_window <= {s_rx_bit_window[19:0], 1'b0};
//			else
//				s_rx_bit_window <= {s_rx_bit_window[19:0], 1'b1};
	end
end

// bit data valid
// 1:valid / 0:invalid(bit-stuffed bit)
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_bit_stuff_den <= 1'b1;
	else if(clk_i) begin
		if(s_rx_clk_en) begin
			if(s_rx_bit_window[5:0] == {6{1'b1}})
				s_rx_bit_stuff_den <= 1'b0;
			else
				s_rx_bit_stuff_den <= 1'b1;
		end
	end
end

assign rx_data_o = s_rx_bit_window[0];
assign rx_den_o  = s_rx_clk_en & s_rx_bit_stuff_den;

// --------------------
// TX
// --------------------
// tx enable
always @(negedge rst_ni, posedge clk_i)
begin
    if(~rst_ni)
		s_tx_request <= 1'b0;
    else if(clk_i) begin
		if (tx_request_i)
			s_tx_request <= 1'b1;
		else if(s_eop_det)
			s_tx_request <= 1'b0;
    end
end

always @(negedge rst_ni, posedge clk_i)
begin
    if(~rst_ni) begin
		s_tx_request_en <= 1'b0;
    end else if(clk_i) begin
		if (s_state == FSM_IDLE)
			s_tx_en <= s_tx_request;
		else if(s_eop_det)
			s_tx_en <= 1'b0;
    end
end








assign tx_busy_o = s_tx_en;

endmodule
// --------------------
