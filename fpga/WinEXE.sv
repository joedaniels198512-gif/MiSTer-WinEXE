// SPDX-License-Identifier: GPL-2.0-or-later
// WinEXE: ARM writes 640x480x32 BGRX at 0x30000000; ascal displays it.
// Direct PAL8 prototype: optional 640x480x8 at 0x30200000 + 256-entry
// palette at 0x3024B000. Mailbox 0x30400000 bit0 selects PAL8 vs BGRX.
// Pixel scanout stays on ascal's vbuf port. DDRAM_* is only a mailbox
// + rare 1 KB palette reader (pal8_fbctl).

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

assign VIDEO_ARX = 12'd4;
assign VIDEO_ARY = 12'd3;

`ifdef MISTER_FB
// BGRX fallback literals kept for GHA sanity + desktop path:
//   32'h3000_0000  12'd640  12'd480  14'd2560  5'b10110
// PAL8: [2:0]=011 indexed, base 0x30200000, stride 640.
wire pal8_en;
assign FB_EN          = 1'b1;
assign FB_FORMAT      = pal8_en ? 5'b00011 : 5'b10110;
assign FB_WIDTH       = 12'd640;
assign FB_HEIGHT      = 12'd480;
assign FB_BASE        = pal8_en ? 32'h3020_0000 : 32'h3000_0000;
assign FB_STRIDE      = pal8_en ? 14'd640 : 14'd2560;
assign FB_FORCE_BLANK = 1'b0;
`endif

`include "build_id.v"
// Status bits (OSD only; not wired into video/audio RTL):
//   [0]     T/R Reset
//   [5]     Restart
//   [6]     Stop
// F0 .WEX picker is handled on the ARM (user_io_file_tx intercept).
localparam CONF_STR = {
	"WinEXE;;",
	"-;",
	"F0,WEX,Load Application...;",
	"-;",
	"T[5],Restart;",
	"T[6],Stop;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"V,v",`BUILD_DATE
};

wire        clk_sys;
wire        forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys)
);

`ifdef MISTER_FB_PALETTE
pal8_fbctl pal8_fbctl
(
	.clk(clk_sys),
	.reset(RESET),
	.vbl(FB_VBL),
	.pal8_en(pal8_en),
	.DDRAM_CLK(DDRAM_CLK),
	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),
	.DDRAM_WE(DDRAM_WE),
	.FB_PAL_CLK(FB_PAL_CLK),
	.FB_PAL_ADDR(FB_PAL_ADDR),
	.FB_PAL_DOUT(FB_PAL_DOUT),
	.FB_PAL_WR(FB_PAL_WR)
);
`else
assign pal8_en = 1'b0;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;
`endif

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),
	.forced_scandoubler(forced_scandoubler),
	.buttons(buttons),
	.status(status),
	.status_menumask(0),
	.ps2_key(ps2_key)
);

wire HBlank, HSync, VBlank, VSync, ce_pix;

vga640 vga640
(
	.clk(clk_sys),
	.ce_pix(ce_pix),
	.HBlank(HBlank),
	.HSync(HSync),
	.VBlank(VBlank),
	.VSync(VSync)
);

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;
assign VGA_DE    = ~(HBlank | VBlank);
assign VGA_HS    = HSync;
assign VGA_VS    = VSync;
assign VGA_R     = 8'd0;
assign VGA_G     = 8'd0;
assign VGA_B     = 8'd0;

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER = act_cnt[26] ? act_cnt[25:18] > act_cnt[7:0] : act_cnt[25:18] <= act_cnt[7:0];

endmodule
