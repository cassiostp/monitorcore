// iosys_bl616 response handling (tangcore#4), through the real UARTs: a
// get-core-ID request that arrives while a joypad or FDD frame is going out
// must be answered after that frame, not acknowledged away by it; and RX
// must keep listening while a reply is still owed, so HID and core_config
// frames sent during a long config-string reply are not lost.
//
// Adapted from nestang sim/saveram/tb_system_save.v (the same MCU model and
// frame parser), minus the save channel monitorcore does not have.
// run.sh compiles a sim copy of iosys with the 20 ms joypad rate limit
// shortened, so a pad change is due within ~0.1 ms here.

`timescale 1ns/1ps

module tb_iosys_response;

localparam real BIT = 500.0;            // MCU UART: 2 Mbaud

// send_state encodings in iosys_bl616.v
localparam SEND_CONFIG_STRING = 2;
localparam SEND_JOYPAD = 3;
localparam SEND_FDD_READ = 5;
localparam SEND_HEADER = 6;

reg clk = 0;
always #23.28 clk = ~clk;               // 21.477 MHz
reg resetn = 0;

reg  [11:0] joy1 = 0, joy2 = 0;
reg  [1:0]  fdd_request = 0;
reg  [15:0] mgmt_readdata = 16'h3412;
reg         uart_rx = 1;
wire        uart_tx;
wire [15:0] hid1, hid2;
wire [31:0] core_config;

iosys_bl616 #(.FREQ(21_477_000), .CORE_ID(0)) dut (
    .clk(clk), .hclk(clk), .resetn(resetn),
    .overlay(), .overlay_x(8'h00), .overlay_y(8'h00), .overlay_color(),
    .joy1(joy1), .joy2(joy2), .hid1(hid1), .hid2(hid2),
    .rom_loading(), .rom_do(), .rom_do_valid(),
    .mgmt_address(), .mgmt_read(), .mgmt_readdata(mgmt_readdata),
    .mgmt_write(), .mgmt_writedata(), .fdd_request(fdd_request),
    .kbd_data(8'h0), .kbd_data_valid(),
    .core_config(core_config),
    .uart_rx(uart_rx), .uart_tx(uart_tx)
);

// ---- MCU side: receive and parse the FPGA's frames ----
wire [7:0] cap_data;
wire cap_valid;
async_receiver #(.ClkFrequency(21_477_000), .Baud(2_000_000)) cap (
    .clk(clk), .RxD(uart_tx), .RxD_data(cap_data), .RxD_data_ready(cap_valid)
);

integer errs = 0;
integer pos = 0, flen = 0;
reg [7:0] ftype = 0;
reg [7:0] fbuf [0:1023];
reg [7:0] cfgbuf [0:255];
integer cfg_len = 0;
integer n_id = 0, n_cfg = 0, n_joy = 0, n_fddr = 0;
reg [15:0] last_joy1 = 16'hFFFF;
reg [15:0] last_fddr = 16'hFFFF;

always @(posedge clk) if (cap_valid) begin
    if (pos == 0) begin
        if (cap_data == 8'hAA) pos <= 1;
        else begin errs = errs + 1; $display("FAIL t=%0t: junk byte %02x between frames", $time, cap_data); end
    end else if (pos == 1) begin flen <= cap_data << 8; pos <= 2; end
    else if (pos == 2) begin flen <= flen | cap_data; pos <= 3; end
    else if (pos == 3) begin ftype <= cap_data; pos <= 4; end
    else begin
        fbuf[pos - 4] = cap_data;
        if (pos - 4 == flen - 2) begin          // last payload byte
            pos <= 0;
            case (ftype)
            8'h01: begin
                n_id = n_id + 1;
                if (fbuf[0] !== 8'h00) begin errs = errs + 1; $display("FAIL: core id %02x, want 00 (monitor)", fbuf[0]); end
            end
            8'h02: begin
                n_cfg = n_cfg + 1;
                cfg_len = flen;
                for (integer i = 0; i < flen - 1; i = i + 1) cfgbuf[i] = fbuf[i];
            end
            8'h03: begin n_joy = n_joy + 1; last_joy1 = {fbuf[0], fbuf[1]}; end
            8'h05: begin n_fddr = n_fddr + 1; last_fddr = {fbuf[0], fbuf[1]}; end
            default: begin errs = errs + 1; $display("FAIL: unknown frame type %02x", ftype); end
            endcase
        end else
            pos <= pos + 1;
    end
end

// ---- MCU side: send frames ----
task tx_byte(input [7:0] b);
    integer k;
begin
    uart_rx = 1'b0; #BIT;
    for (k = 0; k < 8; k = k + 1) begin uart_rx = b[k]; #BIT; end
    uart_rx = 1'b1; #BIT;
end
endtask

task send_hdr(input [15:0] len, input [7:0] c);
begin tx_byte(8'hAA); tx_byte(len[15:8]); tx_byte(len[7:0]); tx_byte(c); end
endtask

task req_id;  begin send_hdr(16'd1, 8'h01); end endtask
task req_cfg; begin send_hdr(16'd1, 8'h02); end endtask

task wait_id(input integer was, input integer timeout_ns, input [8*64-1:0] what);
    integer t;
begin
    t = 0;
    while (n_id == was && t < timeout_ns) begin #1000; t = t + 1000; end
    if (n_id == was) begin
        errs = errs + 1;
        $display("FAIL t=%0t: %0s (send_state=%0d recv_state=%b req=%b ack=%b)",
                 $time, what, dut.send_state, dut.recv_state, dut.response_req, dut.response_ack);
    end
end
endtask

task wait_cfg(input integer was, input integer timeout_ns, input [8*64-1:0] what);
    integer t;
begin
    t = 0;
    while (n_cfg == was && t < timeout_ns) begin #1000; t = t + 1000; end
    if (n_cfg == was) begin errs = errs + 1; $display("FAIL t=%0t: %0s", $time, what); end
end
endtask

task wait_joy(input [15:0] v, input integer timeout_ns, input [8*64-1:0] what);
    integer t;
begin
    t = 0;
    while (last_joy1 !== v && t < timeout_ns) begin #1000; t = t + 1000; end
    if (last_joy1 !== v) begin
        errs = errs + 1;
        $display("FAIL t=%0t: %0s (MCU still sees %04x)", $time, what, last_joy1);
    end
end
endtask

task wait_fddr(input integer was, input integer timeout_ns, input [8*64-1:0] what);
    integer t;
begin
    t = 0;
    while (n_fddr == was && t < timeout_ns) begin #1000; t = t + 1000; end
    if (n_fddr == was) begin errs = errs + 1; $display("FAIL t=%0t: %0s", $time, what); end
end
endtask

// wait until TX is in `s`, optionally with send_state_next == `nxt` (nxt < 0: don't care)
task wait_send(input integer s, input integer nxt, input integer timeout_ns,
               input [8*64-1:0] what);
    integer t;
    reg seen;
begin
    t = 0; seen = 0;
    while (!seen && t < timeout_ns) begin
        @(posedge clk);
        if (dut.send_state == s[2:0] && (nxt < 0 || dut.send_state_next == nxt[2:0])) seen = 1;
        t = t + 47;
    end
    if (!seen) begin errs = errs + 1; $display("FAIL t=%0t: %0s", $time, what); end
end
endtask

task poll_id;
    integer was;
begin
    was = n_id;
    req_id;
    wait_id(was, 500_000, "core-ID poll unanswered");
end
endtask

integer n0, c0, f0;

initial begin
    $timeformat(-9, 0, "ns", 10);
    // FF power-on state of regs without a reset (Gowin FFs come up 0)
    dut.send_idx = 0; dut.response_req = 0; dut.response_ack = 0;
    dut.response_type = 0; dut.joy1_reg = 0; dut.joy2_reg = 0;
    dut.send_state_next = 0; dut.hid1 = 0; dut.hid2 = 0;

    repeat (20) @(posedge clk);
    resetn = 1;
    repeat (20) @(posedge clk);
    #2000;

    // plain core-ID poll
    poll_id;

    // core-ID request landing during a joypad frame must be answered after it
    n0 = n_id;
    joy1 = 12'h004;
    wait_send(SEND_HEADER, SEND_JOYPAD, 200_000, "joypad frame never started");
    req_id;
    wait_joy(16'h0004, 300_000, "joypad frame not reported");
    wait_id(n0, 300_000, "core-ID request during joypad frame dropped");

    // while the config-string reply (74 bytes) is on the wire, RX must keep
    // listening: HID and core_config frames sent then must land
    c0 = n_cfg;
    req_cfg;
    wait_send(SEND_CONFIG_STRING, -1, 300_000, "config-string reply never started");
    send_hdr(16'd5, 8'h09); tx_byte(8'hA5); tx_byte(8'h01); tx_byte(8'h5A); tx_byte(8'h02);
    send_hdr(16'd5, 8'h03); tx_byte(8'h12); tx_byte(8'h34); tx_byte(8'h56); tx_byte(8'h78);
    #10_000;
    if (hid1 !== 16'hA501 || hid2 !== 16'h5A02) begin
        errs = errs + 1;
        $display("FAIL t=%0t: HID frame lost while a response was pending (hid1=%04x hid2=%04x recv_state=%b)",
                 $time, hid1, hid2, dut.recv_state);
    end
    if (core_config !== 32'h12345678) begin
        errs = errs + 1;
        $display("FAIL t=%0t: core_config frame lost while a response was pending (core_config=%08x)",
                 $time, core_config);
    end
    wait_cfg(c0, 2_000_000, "config-string reply never arrived");
    if (cfg_len != 74 || cfgbuf[0] !== "T" || cfgbuf[1] !== "a" || cfgbuf[2] !== "n" ||
        cfgbuf[3] !== "g" || cfgbuf[8] !== "s") begin
        errs = errs + 1;
        $display("FAIL: config string len=%0d head=%02x%02x%02x%02x", cfg_len,
                 cfgbuf[0], cfgbuf[1], cfgbuf[2], cfgbuf[3]);
    end
    poll_id;

    // core-ID request landing during an FDD read frame must be answered after it
    n0 = n_id; f0 = n_fddr;
    fdd_request = 2'b01;
    wait_send(SEND_HEADER, SEND_FDD_READ, 200_000, "FDD read frame never started");
    req_id;
    fdd_request = 2'b00;
    wait_fddr(f0, 300_000, "FDD read frame not reported");
    if (last_fddr !== 16'h3412) begin
        errs = errs + 1;
        $display("FAIL: FDD read payload %04x, want 3412", last_fddr);
    end
    wait_id(n0, 300_000, "core-ID request during FDD read frame dropped");

    // joypad changes and polls still work at the end
    joy1 = 12'h40C;
    wait_joy(16'h040C, 1_000_000, "final joypad change not reported");
    poll_id;

    $display("tb_iosys_response: %0d id replies, %0d config replies, %0d pad frames, %0d fdd-read frames",
             n_id, n_cfg, n_joy, n_fddr);
    if (errs == 0) $display("tb_iosys_response: PASS");
    else $fatal(1, "tb_iosys_response: FAIL, %0d errors", errs);
    $finish;
end

initial begin
    #50_000_000;
    $fatal(1, "tb_iosys_response: FAIL, global timeout");
end

endmodule
