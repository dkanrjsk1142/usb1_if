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

module usb_phy #(
	parameter USB_VER_1_X  = 1  // 1:USB1.1 / 0:USB1.0
) (
	input  wire                      rst_ni,
	input  wire                      clk_i,        // 24MHz

	// phy - bus control
	output wire                      usb_tx_oe_o, // 1: tx / 0: rx(hi-z)

	output wire                      usb_dp_pull_up_en_o, // connect external pull-up resistor switch
	output wire                      usb_dm_pull_up_en_o, // connect external pull-up resistor switch

	// phy - rx
	input  wire                      usb_rx_dp_i, // weak pull-down(not allowed usb spec)
	input  wire                      usb_rx_dm_i, // weak pull-down(not allowed usb spec)

	// phy - tx
	output wire                      usb_tx_dp_o,
	output wire                      usb_tx_dm_o,

	// logic - rx
	output wire                      rx_data_o, // 
	output wire                      rx_den_o,  // 

	output wire                      rx_packet_st_o, // 1clk pulse after SYNC-detected
	output wire                      rx_packet_ed_o, // 1clk pulse after EOP-detected

	output wire                      rx_se0_det_o, // 1 : d+/d- both 0
	output wire                      rx_se1_det_o, // 1 : d+/d- both 1(error)

	// logic - tx
	input  wire                      tx_data_i, // data stream without sync/eop
	input  wire                      tx_den_i,  // 1clk pulse when idle state. keep TX(line status) until EOP.
	output wire                      tx_busy_o  // 1:ignore tx_den/data
);


localparam [3:0]  USB_CLK_EN_CNTR = (USB_VER_1_X == 1) ? 4'h1, 4'hF;

localparam [1:0]  SE0_STATE      = 2'b00;
localparam [1:0]  J_STATE        = (USB_VER_1_X == 1) ? 2'b10 : 2'b01;
localparam [1:0]  K_STATE        = (USB_VER_1_X == 1) ? 2'b01 : 2'b10;
localparam [1:0]  SE1_STATE      = 2'b11;

localparam [3:0]  FSM_TX_IDLE       = 4'h0; // 
localparam [3:0]  FSM_TX_SYNC       = 4'h1; // check KJKJKJKK (with wdt, goto UNKNOWN after timeout)
localparam [3:0]  FSM_TX_PAYLOAD    = 4'h2; // PID + PAYLOAD (+ CRC)
localparam [3:0]  FSM_TX_EOP        = 4'h3; // SE0 + SE0 + J

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

reg  [ 2:0] s_usb_rx_dp_d;
reg  [ 2:0] s_usb_rx_dm_d;
reg  [ 1:0] s_rx_data; // 0:SE0, 1:J, 2:K, 3:SE1
wire        s_rx_chg_det;


reg  [2*8-1:0] s_rx_symbol_window;
reg            s_sync_det;
reg            s_eop_det;

reg            s_tx_en;

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
assign s_rx_clk_en = ((s_rx_clk_en_cntr == {P_RX_CLK_EN_CNTR_WIDTH{1'b0}}) ? 1'b1 : 1'b0);

// CLK EN counter
// Low Speed  : 1/16 @ 24MHz
// Full Speed :  1/2 @ 24MHz
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_clk_en_cntr <= {P_RX_CLK_EN_CNTR_WIDTH{1'b0};
	else if(clk_i) begin
		if (s_rx_chg_det || (s_rx_clk_en_cntr == USB_CLK_EN_CNTR)) // clk recovery
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
		s_usb_rx_dp_d <= {3{J_STATE[1]}};
		s_usb_rx_dm_d <= {3{J_STATE[0]}};
	end else if(clk_i) begin
		s_usb_rx_dp_d <= {s_usb_rx_dp_d[1:0], usb_rx_dp_i};
		s_usb_rx_dm_d <= {s_usb_rx_dm_d[1:0], usb_rx_dm_i};
	end
end

// something change detected
assign s_rx_chg_det = (^s_usb_rx_dp_d[2:1] | ^s_usb_rx_dm_d[2:1]) ? 1'b1 : 1'b0;

always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_rx_chg_det_1d <= 1'b0;
	else if(clk_i) begin
			s_rx_chg_det_1d <= s_rx_chg_det;
	end
end

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
		s_rx_symbol_window <= {8{J_STATE}};
	else if(clk_i) begin
		if(s_rx_clk_en)
			s_rx_symbol_window <= s_pre_rx_symbol_window;
	end
end

assign s_pre_rx_symbol_window = {s_rx_symbol_window, s_rx_data};

// sync detect
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_sync_det <= 1'b0;
	else if(clk_i) begin
		if(s_tx_en)
			s_sync_det <= 1'b0;
		else if(s_rx_clk_en)
			s_sync_det <= (s_pre_rx_symbol_window == {3{K_STATE, J_STATE}, K_STATE, K_STATE});
	end
end

always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_eop_det  <= 1'b0;
	else if(clk_i) begin
		if(s_tx_en)
			s_eop_det  <= 1'b0;
		else if(s_rx_clk_en)
			s_eop_det <= (s_pre_rx_symbol_window[3*2-1:0] == {SE0_STATE, SE0_STATE, J_STATE});
	end
end

assign rx_packet_st_o = s_rx_clk_en & s_sync_det;
assign rx_packet_ed_o = s_rx_clk_en & s_eop_det;

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
			s_rx_bit_window <= {s_rx_bit_window[5:0], ~s_rx_chg_det_1d};
//			if(s_rx_chg_det_1d)
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
		s_rx_bit_stuff_den <= 2'b11;
	else if(clk_i) begin
		if(s_tx_en)
			s_rx_bit_stuff_den <= 2'b00;
		else if(s_rx_clk_en) begin
			if(s_rx_bit_window[5:0] == {6{1'b1}})
				s_rx_bit_stuff_den <= {s_rx_bit_stuff_den, 1'b0};
			else
				s_rx_bit_stuff_den <= {s_rx_bit_stuff_den, 1'b1};
		end
	end
end

assign rx_data_o = s_rx_bit_window[1];
assign rx_den_o  = s_rx_clk_en & s_rx_bit_stuff_den[1];

assign rx_se0_det_o = (s_rx_data == SE0_STSTE) ? 1'b1 : 1'b0;
assign rx_se1_det_o = (s_rx_data == SE1_STSTE) ? 1'b1 : 1'b0;

// --------------------
// TX
// --------------------
// input ff
// ignore tx_den/data when tx_busy_o=1
always @(negedge rst_ni, posedge clk_i)
begin
    if(~rst_ni) begin
		s_tx_data_1d <= 1'b0;
		s_tx_den_1d <= 1'b0;
    else if(clk_i) begin
		s_tx_data_1d <= tx_data_i;
		//optimize if (tx_den_i & ~s_tx_en) <= 1'b1; else if(~tx_den_i) < 1'b0;
		if (~tx_den_i)
			s_tx_den_1d <= 1'b0;
		else if (~s_tx_en)
			s_tx_den_1d <= 1'b1;
    end
end

// tx enable
always @(negedge rst_ni, posedge clk_i)
begin
    if(~rst_ni)
		s_tx_en <= 1'b0;
    else if(clk_i) begin
		if (s_tx_den_1d)
			s_tx_en <= 1'b1;
		else if(s_tx_next_state == FSM_TX_IDLE)
			s_tx_en <= 1'b0;
    end
end

assign tx_busy_o   = s_tx_en;

// --------------------
// TX - FSM
// --------------------
always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_tx_next_state <= FSM_TX_IDLE;
	else if(clk_i) begin
//		if (s_tx_en) begin
			case (s_tx_state)
				FSM_TX_IDLE:
					if (s_tx_den_1d)
						s_tx_next_state <= FSM_TX_SYNC;
					else
						s_tx_next_state <= FSM_TX_IDLE;
				FSM_TX_SYNC:
					if (s_tx_attach_cntr == 3'h7)
						s_tx_next_state <= FSM_TX_PAYLOAD;
					else
						s_tx_next_state <= s_tx_state;
				FSM_TX_PAYLOAD:
					if (s_tx_buf_empty)
						s_tx_next_state <= FSM_TX_EOP;
					else
						s_tx_next_state <= s_tx_state;
				FSM_TX_EOP:
					if (s_tx_attach_cntr == 3'h2)
						s_tx_next_state <= FSM_TX_PAYLOAD;
					else
						s_tx_next_state <= s_tx_state;
				default:
					s_tx_next_state <= FSM_IDLE;
			endcase
//		end else
//			s_tx_next_state <= FSM_TX_IDLE;
	end
end

always @(negedge rst_ni, posedge clk_i)
begin
	if(~rst_ni)
		s_tx_state <= FSM_IDLE;
	else if(clk_i)
		s_tx_state <= s_tx_next_state;
end

// --------------------
// TX - buffer
//      for attach sync/eop and bit-stuffing
//      BUF_ADDR_WIDTH(2048bits) > max data size(sync + pid + 1024bytes + crc + eop)
// --------------------
buffer #(
	.SYNC_MODE            ("sync"              ), // parameter SYNC_MODE      =  "sync", // "async" : (clk_enqueue_i - clk_dequeue_i is different clk) / "sync" : (same clk)

	.BUF_ADDR_WIDTH       (11                  ), // parameter BUF_ADDR_WIDTH = 8, // BUF_SIZE = 2^BUF_ADR_WIDTH
	.DATA_BIT_WIDTH       (1                   ), // parameter DATA_BIT_WIDTH = 8, // 
	.WAIT_DELAY           (1                   )  // parameter WAIT_DELAY     = 0  // wait reply delay(0:no wait reply from receive module)
) u_rx_buffer (
	.rst_ni               (rst_ni              ), // input  wire                      rst_ni,
	.clk_enqueue_i        (clk_i               ), // input  wire                      clk_enqueue_i,
	.clk_dequeue_i        (clk_i               ), // input  wire                      clk_dequeue_i,
	.enqueue_den_i        (s_tx_den_1d         ), // input  wire                      enqueue_den_i,
	.enqueue_data_i       (s_tx_data_1d        ), // input  wire [DATA_BIT_WIDTH-1:0] enqueue_data_i,
	.is_queue_full_o      (                    ), // output wire                      is_queue_full_o,
	.dequeue_wait_i       (s_tx_buf_wait       ), // input  wire                      dequeue_wait_i,
	.dequeue_den_o        (s_tx_buf_den        ), // output wire                      dequeue_den_o,
	.dequeue_data_o       (s_tx_buf_data       ), // output wire [DATA_BIT_WIDTH-1:0] dequeue_data_o,
	.is_queue_empty_o     (s_tx_buf_empty      )  // output wire                      is_queue_empty_o // loosy empty status(there is some delay after queue is empty)
);

// buffer wait control
always @(negedge rst_ni, posedge clk_i)
begin
    if(~rst_ni)
		s_tx_buf_wait <= 1'b0;
    else if(clk_i) begin
		case (s_tx_next_state)
			//FSM_TX_IDLE:
			//	s_tx_buf_wait <= 1'b0;
			FSM_TX_SYNC:
				s_tx_buf_wait <= 1'b1;
			FSM_TX_PAYLOAD:
				if (s_tx_ins_bit_stuff)
					s_tx_buf_wait <= 1'b1;
				else
					s_tx_buf_wait <= 1'b0;
			//FSM_TX_EOP:
			//	s_tx_buf_wait <= 1'b0;
			default:
				s_tx_buf_wait <= 1'b0;
		endcase
    end
end

// --------------------
// TX - insert bit-stuff & drive bus
// --------------------
// counter to generate sync/eop
always @(negedge rst_ni, posedge clk_i)
begin
    if(~rst_ni) begin
		s_tx_attach_cntr <= 3'b0;
    end else if(clk_i) begin
		if (s_tx_state == FSM_TX_SYNC || s_tx_state == FSM_TX_EOP)
			s_tx_attach_cntr <= s_tx_attach_cntr + 1'b1;
		else
			s_tx_attach_cntr <= 3'b0;
    end
end

//bit-window(for bit-stuff)


//symbol-window(for drive bus)



	input  wire                      tx_data_i // data stream except sync/crc/eop
	input  wire                      tx_den_i  // 1clk pulse when idle state. keep TX(line status) until EOP.



endmodule
// --------------------
