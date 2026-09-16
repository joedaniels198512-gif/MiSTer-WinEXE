// SPDX-License-Identifier: GPL-2.0-or-later
// Dummy 640x480 progressive raster so sys_top has CE_PIXEL / VGA_*.
// HDMI pixels come from MISTER_FB / ascal, not this raster.

module vga640
(
	input         clk,
	output        ce_pix,
	output        HBlank,
	output        HSync,
	output        VBlank,
	output        VSync
);

localparam [9:0] H_ACTIVE = 10'd640;
localparam [9:0] H_TOTAL  = 10'd800;
localparam [9:0] HS_START = 10'd656;
localparam [9:0] HS_END   = 10'd752;
localparam [9:0] V_ACTIVE = 10'd480;
localparam [9:0] V_TOTAL  = 10'd525;
localparam [9:0] VS_START = 10'd490;
localparam [9:0] VS_END   = 10'd492;

reg [9:0] hc = 0;
reg [9:0] vc = 0;

assign ce_pix = 1'b1;

always @(posedge clk) begin
	if (hc == (H_TOTAL - 10'd1)) begin
		hc <= 10'd0;
		if (vc == (V_TOTAL - 10'd1))
			vc <= 10'd0;
		else
			vc <= vc + 10'd1;
	end else begin
		hc <= hc + 10'd1;
	end
end

assign HBlank = (hc >= H_ACTIVE);
assign VBlank = (vc >= V_ACTIVE);
assign HSync  = (hc >= HS_START) && (hc < HS_END);
assign VSync  = (vc >= VS_START) && (vc < VS_END);

endmodule
