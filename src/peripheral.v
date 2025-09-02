/*
 * Copyright (c) 2025 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Change the name of this module to something that reflects its functionality and includes your name for uniqueness
// For example tqvp_yourname_spi for an SPI peripheral.
// Then edit tt_wrapper.v line 41 and change tqvp_example to your chosen module name.
module tqvp_example (
    input         clk,          // Clock - the TinyQV project clock is normally set to 64MHz.
    input         rst_n,        // Reset_n - low to reset.

    input  [7:0]  ui_in,        // The input PMOD, always available.  Note that ui_in[7] is normally used for UART RX.
                                // The inputs are synchronized to the clock, note this will introduce 2 cycles of delay on the inputs.

    output [7:0]  uo_out,       // The output PMOD.  Each wire is only connected if this peripheral is selected.
                                // Note that uo_out[0] is normally used for UART TX.

    input [5:0]   address,      // Address within this peripheral's address space
    input [31:0]  data_in,      // Data in to the peripheral, bottom 8, 16 or all 32 bits are valid on write.

    // Data read and write requests from the TinyQV core.
    input [1:0]   data_write_n, // 11 = no write, 00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    input [1:0]   data_read_n,  // 11 = no read,  00 = 8-bits, 01 = 16-bits, 10 = 32-bits
    
    output [31:0] data_out,     // Data out from the peripheral, bottom 8, 16 or all 32 bits are valid on read when data_ready is high.
    output        data_ready,

    output        user_interrupt  // Dedicated interrupt request for this peripheral
);

    localparam SREG_LEN = 64;
    localparam SREG_NUM = 6;
    reg [SREG_LEN-1:0] sreg[0:SREG_NUM-1];

    always @(posedge clk) begin
        if (!rst_n) begin
            integer i;
            for (i=0; i < SREG_NUM; i=i+1) begin
                sreg[i] <= {SREG_LEN{1'b0}};
            end
        end else if (~pix_x[10] & (&pix_x[3:0])) begin
            integer i;
            for (i=0; i < SREG_NUM; i=i+1) begin
                sreg[i] <= { sreg[i][0], sreg[i][SREG_LEN-1:1]};  // shift right
            end
        end
    end

    reg [SREG_NUM-1:0] scope_value;
    integer j;
    always @* begin
        for (j=0; j < SREG_NUM; j=j+1) begin
            scope_value[j] = sreg[j][0];
        end
    end

    // ----- HOST INTERFACE -----

    localparam REG_PUSHVAL = 6'h00;
    localparam REG_BG_COLOR = 6'h01;
    localparam REG_TEXT_COLOR = 6'h02;
    localparam REG_STATUS = 6'h3F;

    reg [5:0] text_color;  // Text color
    reg [5:0] bg_color;  // Background color
    reg [5:0] new_value;  // New value to push into shift register
    reg valid;
    
    // Writes (only write lowest 8 bits)
    always @(posedge clk) begin
        if (!rst_n) begin
            bg_color <= 6'b010000;
            text_color <= 6'b110011;
            new_value <= 6'b000000;
            valid <= 0;
        end else begin
            if (~&data_write_n) begin
                if (address == REG_BG_COLOR) begin
                    bg_color <= data_in[5:0];
                end else if (address == REG_TEXT_COLOR) begin
                    text_color <= data_in[5:0];
                end else if ((address == REG_PUSHVAL) && !valid) begin
                    new_value <= data_in[5:0];
                    valid <= 1;
                end
            end else begin
                valid <= 0;
            end
        end
    end

    // Register reads
    assign data_out = (&address) ? {29'b0, hsync, vsync, interrupt} : 32'h0;  // REG_STATUS

    // All reads complete in 1 clock
    assign data_ready = 1;
    
    // --- Interrupt handling ---
    reg interrupt;
    assign user_interrupt = interrupt;

    always @(posedge clk) begin
        if (!rst_n) begin
            interrupt <= 0;
        end else begin
            if ((y_hi == 5'd16) && !(|y_lo) && (~|pix_x)) begin
                interrupt <= 1;
            end else if ((&address) & (~&data_read_n)) begin  // read REG_VGA
                interrupt <= 0;
            end
        end
    end

    // ----- VGA INTERFACE -----

    // VGA signals
    wire hsync, vsync, blank;
    reg [1:0] R, G, B;
    wire [10:0] pix_x;
    wire [10:0] pix_y;
    wire [5:0] y_lo;
    wire [4:0] y_hi;

    // TinyVGA PMOD
    assign uo_out = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};

    vga_timing hvsync_gen (
        .clk(clk),
        .rst_n(rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .blank(blank),
        .x_lo(pix_x[4:0]),
        .x_hi(pix_x[10:5]),
        .y_lo(y_lo),
        .y_hi(y_hi)
    );

    assign pix_y = ({6'b0, y_hi} << 5) + ({6'b0, y_hi} << 4) + {5'b0, y_lo};  // pix_y = y_hi * 48 + y_lo
    wire [3:0] y_blk = pix_y[10:7];  // 128-pixel high blocks
    wire frame_active = (~pix_x[10]) && (y_blk < 4'h6);  // active area is 1024x768
    
    wire pixel_on = frame_active && (pix_y[9:4] == scope_value);

    always @(posedge clk) begin
        if (!rst_n) begin
            {B, G, R} <= 6'b000000;
        end else begin
            {B, G, R} <= blank ? 6'b000000 : (pixel_on ? text_color : bg_color);
        end
    end

endmodule
