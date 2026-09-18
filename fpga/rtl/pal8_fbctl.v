// SPDX-License-Identifier: GPL-2.0-or-later
// Direct PAL8 prototype: poll mailbox on VBlank, load 256-entry palette
// into ascal pal2 (FB_PAL_*) only when the generation changes.
//
// Palette transport: FPGA reads shared DDR (option A). ARM already writes
// 00RRGGBB entries next to the PAL8 pixels. No new HPS PIO. Palette
// updates are rare vs scanout, so a 1 KB load on gen change is enough.
// Single-beat DDRAM reads avoid missing Avalon readdatavalid pulses.
//
// Mailbox 0x30400000 (little-endian 32-bit words):
//   +0 magic 0x50384C38 'P8L8'
//   +4 flags bit0 = pal8_en
//   +8 palette generation
//   +C present count (ignored by FPGA)
// Palette 0x3024B000: 256 × 32-bit 00RRGGBB
//
// DDRAM_ADDR is byte[31:3]. ascal remains the pixel consumer (vbuf port).

module pal8_fbctl
(
	input         clk,
	input         reset,
	input         vbl,

	output reg    pal8_en,

	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output reg    DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	output        FB_PAL_WR
);

localparam [28:0] MBOX_ADDR = 29'h06080000; // 0x30400000 >> 3
localparam [28:0] PAL_ADDR  = 29'h06049600; // 0x3024B000 >> 3
localparam [31:0] MAGIC     = 32'h50384C38; // 'P8L8'

localparam S_IDLE     = 3'd0;
localparam S_REQ      = 3'd1;
localparam S_WAIT     = 3'd2;
localparam S_MB1_REQ  = 3'd3;
localparam S_MB1_WAIT = 3'd4;
localparam S_PAL_HI   = 3'd5;
localparam S_PAL_NEXT = 3'd6;

reg  [2:0]  state;
reg         vbl_d, vbl_d2;
reg  [28:0] addr;
reg  [7:0]  beat;
reg  [31:0] last_gen;
reg  [31:0] seen_gen;
reg  [7:0]  pal_idx;
reg  [23:0] pal_rgb;
reg         pal_wr;
reg  [63:0] beat_q;
reg         magic_ok;
reg         want_en;
reg  [2:0]  after_wait;

assign DDRAM_CLK      = clk;
assign DDRAM_DIN      = 64'd0;
assign DDRAM_BE       = 8'hFF;
assign DDRAM_WE       = 1'b0;
assign DDRAM_BURSTCNT = 8'd1;
assign DDRAM_ADDR     = addr;
assign FB_PAL_CLK     = clk;
assign FB_PAL_ADDR    = pal_idx;
assign FB_PAL_DOUT    = pal_rgb;
assign FB_PAL_WR      = pal_wr;

always @(posedge clk) begin
	vbl_d  <= vbl;
	vbl_d2 <= vbl_d;
	pal_wr <= 1'b0;

	if (reset) begin
		state      <= S_IDLE;
		pal8_en    <= 1'b0;
		DDRAM_RD   <= 1'b0;
		last_gen   <= 32'hFFFF_FFFF;
		seen_gen   <= 32'd0;
		addr       <= 29'd0;
		beat       <= 8'd0;
		pal_idx    <= 8'd0;
		magic_ok   <= 1'b0;
		want_en    <= 1'b0;
		after_wait <= S_IDLE;
	end else begin
		if (!DDRAM_BUSY)
			DDRAM_RD <= 1'b0;

		case (state)
			S_IDLE: begin
				if (vbl_d & ~vbl_d2) begin
					addr       <= MBOX_ADDR;
					after_wait <= S_MB1_REQ;
					state      <= S_REQ;
				end
			end

			S_REQ: begin
				if (!DDRAM_BUSY) begin
					DDRAM_RD <= 1'b1;
					state    <= S_WAIT;
				end
			end

			S_WAIT: begin
				if (DDRAM_DOUT_READY) begin
					beat_q <= DDRAM_DOUT;
					state  <= after_wait;
				end
			end

			S_MB1_REQ: begin
				// beat0 = {flags, magic}
				magic_ok <= (beat_q[31:0] == MAGIC);
				want_en  <= beat_q[32];
				addr     <= MBOX_ADDR + 29'd1; // +8 bytes
				after_wait <= S_MB1_WAIT;
				state    <= S_REQ;
			end

			S_MB1_WAIT: begin
				// beat1 = {presents, pal_gen} already in beat_q
				seen_gen <= beat_q[31:0];
				if (!magic_ok || !want_en) begin
					pal8_en <= 1'b0;
					state   <= S_IDLE;
				end else begin
					pal8_en <= 1'b1;
					if (beat_q[31:0] == last_gen)
						state <= S_IDLE;
					else begin
						addr    <= PAL_ADDR;
						beat    <= 8'd0;
						pal_idx <= 8'd0;
						after_wait <= S_PAL_HI;
						state   <= S_REQ;
					end
				end
			end

			S_PAL_HI: begin
				pal_rgb <= beat_q[23:0];
				pal_wr  <= 1'b1;
				state   <= S_PAL_NEXT;
			end

			S_PAL_NEXT: begin
				pal_idx <= pal_idx + 8'd1;
				pal_rgb <= beat_q[55:32];
				pal_wr  <= 1'b1;
				if (beat == 8'd127) begin
					last_gen <= seen_gen;
					state    <= S_IDLE;
				end else begin
					beat       <= beat + 8'd1;
					addr       <= PAL_ADDR + {21'd0, beat + 8'd1};
					after_wait <= S_PAL_HI;
					state      <= S_REQ;
				end
			end

			default: state <= S_IDLE;
		endcase
	end
end

endmodule
