#!/bin/sh
# iosys response-handling sim (iverilog). From this directory:
#   ./run.sh              compile and run the testbench
# Gowin tolerates the "input reg" port declaration in the source; iverilog
# does not, so run.sh compiles a sim-only copy with it softened, and with
# the 20 ms joypad rate limit shortened. -DSIM drops the textdisp overlay.
set -e
RTL=../../src
sed -e 's/input reg  \[7:0\] kbd_data/input [7:0] kbd_data/' \
    -e 's/^\( *\)kbd_data <= rx_data;/\1;                       \/\/ sim: kbd path idle/' \
    -e 's|localparam JOY_UPDATE_INTERVAL = 50_000_000 / 50;|localparam JOY_UPDATE_INTERVAL = 2_000;|' \
    $RTL/iosys/iosys_bl616.v > iosys_sim.v
grep -q "JOY_UPDATE_INTERVAL = 2_000" iosys_sim.v
iverilog -g2012 -DSIM -o tb_iosys_response.out \
    tb_iosys_response.v iosys_sim.v $RTL/iosys/uart_fixed.v
vvp tb_iosys_response.out
