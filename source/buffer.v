// --------------------------------------------------------
// File Name   : buffer.v
// Description : buffer controlled by dequeue_wait
//               BUSY_DELAY=2 example
//                        0   1   2   3   4   5   6   7   8   9   10  11  12  13  14  15  16  17  18  19  20  21  22  23
//                   clk  --__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__--__
//         enqueue_den_i  ____----____________------------________________________________________________________________
//        s_enqueue_addr  0           1               2   3   4                                                           
//            buffer_cnt  0           1       0       1   2   3       2   1   2           1   0   1       0               
//         s_dequeue_den  ________________----____________________--------____________--------________----________________
//        s_dequeue_addr  0                   1                       2   3   2           3   4   3       4               
//s_deq~addr_before_wait  0               1                       2                   3               4                   
//         dequeue_den_o  ____________________----____________________--------____________--------________----____________
//        dequeue_wait_i  ____________________________------------____________--------____________----____________----____
//
//****used by receiving module(check *)       ****                    ****                ****            ****
//     -> exsample receive module can handle only 1 data
//        (dequeue_wait_i signal income from receive module)
// --------------------------------------------------------
// Ver     Date       Author              Comment
// 0.01    2020.01.03 I.Yang              reduce function
// 0.02    2020.01.04 I.Yang              add generate - support BUSY_DELAY=0(burst rd)
// 0.03    2020.01.04 I.Yang              support dual-clk
// 0.04    2020.01.11 I.Yang              change name wr/rd -> enqueue/dequeue
//                                        change name busy -> wait
//                                        change name en -> en(data_en)
// 0.05    2020.01.11 I.Yang              change wait handling
//                                            origin : flush after wait
//                                            change : flush without wait and
//                                                     restore dequeue address after wait
// 0.06    2020.01.19 I.Yang              add async address check(sync only -> async support)
//                                        -> select by parameter
//                                        -> manage by gray code
//                                        add status(empty/full) pin
// 0.07    2020.02.01 I.Yang              support negative value WAIT_DELAY
//
// --------------------------------------------------------

`timescale 1ns / 1ps

module buffer #(
	parameter SYNC_MODE      =  "sync", // "async" : (clk_enqueue_i - clk_dequeue_i is different clk) / "sync" : (same clk)
	parameter BUF_ADDR_WIDTH =       8, // BUF_SIZE = 2^BUF_ADR_WIDTH
	parameter DATA_BIT_WIDTH =       8, // 
	parameter WAIT_DELAY     =       0  // wait reply delay(0:no wait reply from receive module)
) (
	input  wire                      rst_ni,
	input  wire                      clk_enqueue_i,
	input  wire                      clk_dequeue_i,
	// enqueue clk domain
	input  wire                      enqueue_den_i,
	input  wire [DATA_BIT_WIDTH-1:0] enqueue_data_i,
	output wire                      is_queue_full_o,

	// dequeue clk domain
	input  wire                      dequeue_wait_i,
	output wire                      dequeue_den_o,
	output wire [DATA_BIT_WIDTH-1:0] dequeue_data_o,
	output wire                      is_queue_empty_o // loosy empty status(there is some delay after queue is empty)
);

localparam BUF_SIZE = 2 ** BUF_ADDR_WIDTH;

reg  [DATA_BIT_WIDTH-1:0] RAM [BUF_SIZE-1:0];

reg                       s_enqueue_den_1d;
wire                      s_dequeue_den;
reg                       s_dequeue_den_1d;

reg  [DATA_BIT_WIDTH-1:0] s_enqueue_data_1d;
reg  [DATA_BIT_WIDTH-1:0] s_dequeue_data;

reg  [BUF_ADDR_WIDTH-1:0] s_enqueue_addr;
reg  [BUF_ADDR_WIDTH-1:0] s_dequeue_addr;

reg  [BUF_ADDR_WIDTH-1:0] s_dequeue_addr_before_wait;
wire signed [BUF_ADDR_WIDTH  :0] s_dequeue_addr_diff; // signed arith with WAIT_DELAY

reg                       s_dequeue_wait_1d;

reg                       s_full;
reg                       s_full_out;
reg                 [1:0] s_full_d;
wire                      s_empty;


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
// RAM (automatically synthesis)
// --------------------
// input FF for BRAM
always @(negedge rst_ni, posedge clk_enqueue_i)
begin
	if(~rst_ni) begin
		s_enqueue_den_1d  <= 1'b0;
		s_enqueue_data_1d <= {DATA_BIT_WIDTH{1'b0}};
	end else if(clk_enqueue_i) begin
		s_enqueue_den_1d  <= enqueue_den_i & ~s_full;
		s_enqueue_data_1d <= enqueue_data_i;
	end
end

// write
always @(posedge clk_enqueue_i)
begin
	if (s_enqueue_den_1d)
		RAM[s_enqueue_addr] <= s_enqueue_data_1d;
end

// read(1clk-dly)
always @(posedge clk_dequeue_i)
begin
//	if (s_dequeue_den) // del Ver0.05
		s_dequeue_data <= RAM[s_dequeue_addr];
end


// --------------------
// Async synchronizer
// synchronize address for check empty/full status info.
// There is synchonizing delay but not affect when queue is not empty nor full.
// --------------------
generate if (SYNC_MODE == "async") // async - graycode synchronize
begin
	reg  [BUF_ADDR_WIDTH-1:0] s_enqueue_addr_gray;
	reg  [BUF_ADDR_WIDTH-1:0] s_dequeue_addr_gray;
	reg  [BUF_ADDR_WIDTH-1:0] s_enqueue_addr_gray_1d;
	reg  [BUF_ADDR_WIDTH-1:0] s_dequeue_addr_gray_1d;
	reg  [BUF_ADDR_WIDTH-1:0] s_enqueue_addr_gray_2d;
	reg  [BUF_ADDR_WIDTH-1:0] s_dequeue_addr_gray_2d;
	reg  [BUF_ADDR_WIDTH-1:0] s_enqueue_addr_gray_3d;
	
	// graycode of enqueue address
	always @(negedge rst_ni, posedge clk_enqueue_i)
	begin
		if(~rst_ni)
			s_enqueue_addr_gray <= {BUF_ADDR_WIDTH{1'b0}};
		else if(clk_enqueue_i) begin
			if (s_enqueue_den_1d)
				s_enqueue_addr_gray <= bin2gray(s_enqueue_addr);
		end
	end
	
	// synchronizer(enqueue->dequeue)
	always @(negedge rst_ni, posedge clk_dequeue_i)
	begin
		if(~rst_ni) begin
			s_enqueue_addr_gray_1d <= {BUF_ADDR_WIDTH{1'b0}};
			s_enqueue_addr_gray_2d <= {BUF_ADDR_WIDTH{1'b0}};
			s_enqueue_addr_gray_3d <= {BUF_ADDR_WIDTH{1'b0}};
		end else if(clk_enqueue_i) begin
			s_enqueue_addr_gray_1d <= s_enqueue_addr_gray;
			s_enqueue_addr_gray_2d <= s_enqueue_addr_gray_1d;
			s_enqueue_addr_gray_3d <= s_enqueue_addr_gray_2d; // delay after s_full_2d is confirmed.
		end
	end
	
	// graycode of dequeue address(use exactly dequeued data's address)
	always @(negedge rst_ni, posedge clk_dequeue_i)
	begin
		if(~rst_ni)
			s_dequeue_addr_gray <= {BUF_ADDR_WIDTH{1'b0}};
		else if(clk_dequeue_i) begin
			if (s_dequeue_den)
				s_dequeue_addr_gray <= bin2gray(s_dequeue_addr);
			else if (dequeue_wait_i & ~s_dequeue_wait_1d) // posedge
				s_dequeue_addr_gray <= bin2gray(s_dequeue_addr_before_wait - 1'b1);
		end
	end
	
	// synchronizer(dequeue->enqueue)
	always @(negedge rst_ni, posedge clk_enqueue_i)
	begin
		if(~rst_ni) begin
			s_dequeue_addr_gray_1d <= {BUF_ADDR_WIDTH{1'b0}};
			s_dequeue_addr_gray_2d <= {BUF_ADDR_WIDTH{1'b0}};
		end else if(clk_dequeue_i) begin
			s_dequeue_addr_gray_1d <= s_dequeue_addr_gray;
			s_dequeue_addr_gray_2d <= s_dequeue_addr_gray_1d;
		end
	end
	
	// status
	always @(negedge rst_ni, posedge clk_enqueue_i)
	begin
		if(~rst_ni)
			s_full <= 1'b0;
		else if(clk_enqueue_i) begin
			// if enqueue_addr + 2 == s_dequeue_addr, full. 
			// but, gray_addr is addr + 1. so this comparison is correct.
			if (~s_empty && bin2gray(s_enqueue_addr + 1'b1) == s_dequeue_addr_gray_2d) begin
				if (s_enqueue_den_1d)
					s_full <= 1'b1;
				else
					s_full <= 1'b0;
			end
		end
	end

	// synchronizer(enqueue->dequeue)
	always @(negedge rst_ni, posedge clk_dequeue_i)
	begin
		if(~rst_ni)
			s_full_d <= 2'b0;
		else if(clk_dequeue_i)
			s_full_d <= {s_full_d, s_full};
	end
	
	assign s_empty = (~s_full_d[1] && s_enqueue_addr_gray_3d == s_dequeue_addr_gray) ? 1'b1 : 1'b0;
end
else // sync - no synchronizer
begin
	// status
	always @(negedge rst_ni, posedge clk_enqueue_i)
	begin
		if(~rst_ni)
			s_full <= 1'b0;
		else if(clk_enqueue_i) begin
			if (~s_empty && ((s_enqueue_addr + 2'h2) == s_dequeue_addr)) begin
				if (s_enqueue_den_1d)
					s_full <= 1'b1;
				else
					s_full <= 1'b0;
			end
		end
	end

	always @(negedge rst_ni, posedge clk_enqueue_i)
	begin
		if(~rst_ni)
			s_full_d <= 2'b0;
		else if(clk_enqueue_i)
			s_full_d <= {s_full_d, s_full};
	end
	
	assign s_empty = (~s_full_d[0] && s_enqueue_addr == s_dequeue_addr) ? 1'b1 : 1'b0;
end
endgenerate

// --------------------
// TX
// --------------------
// mod Ver0.05 start
assign s_dequeue_den = ~dequeue_wait_i && ~s_empty ? 1'b1 : 1'b0;

always @(negedge rst_ni, posedge clk_dequeue_i)
begin
	if(~rst_ni) begin
		s_dequeue_wait_1d <= 1'b0;
		s_dequeue_den_1d  <= 1'b0;
	end else if(clk_dequeue_i) begin
		s_dequeue_wait_1d <= dequeue_wait_i;
		s_dequeue_den_1d  <= s_dequeue_den;
	end
end

always @(negedge rst_ni, posedge clk_dequeue_i)
begin
	if(~rst_ni)
		s_dequeue_addr_before_wait <= {{BUF_ADDR_WIDTH{1'b0}}, 1'b1}; // for make graycode
	else if(clk_dequeue_i) begin
		if (s_dequeue_den & ~s_dequeue_den_1d) // posedge
			s_dequeue_addr_before_wait <= s_dequeue_addr + 1'b1;
		else if ($signed(s_dequeue_addr_diff) >= $signed(WAIT_DELAY[BUF_ADDR_WIDTH:0]))
			s_dequeue_addr_before_wait <= s_dequeue_addr - WAIT_DELAY[BUF_ADDR_WIDTH-1:0];
	end
end

assign s_dequeue_addr_diff = s_dequeue_addr - s_dequeue_addr_before_wait;

// TX RAM address
always @(negedge rst_ni, posedge clk_dequeue_i)
begin
	if(~rst_ni)
		s_dequeue_addr <= {{BUF_ADDR_WIDTH{1'b0}}, 1'b1};
	else if(clk_dequeue_i) begin
		if (s_dequeue_den)
			s_dequeue_addr <= s_dequeue_addr + 1'b1;
		else if (dequeue_wait_i & ~s_dequeue_wait_1d) // posedge
			s_dequeue_addr <= s_dequeue_addr_before_wait;
	end
end
// mod Ver0.05 end

assign dequeue_data_o = s_dequeue_data;
assign dequeue_den_o  = s_dequeue_den_1d;

// 1clk "enqueue_clk" delay out signal for enqueuing device
always @(negedge rst_ni, posedge clk_enqueue_i)
begin
	if(~rst_ni)
		s_full_out <= 1'b0;
	else if(clk_enqueue_i)
		s_full_out <= s_full;
end
assign is_queue_full_o  = s_full_out;
assign is_queue_empty_o = s_empty;

endmodule
