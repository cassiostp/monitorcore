// Tang Console 60K/138K monitor clocks
create_clock -name sys_clk -period 20 [get_ports {sys_clk}]         // 50 MHz
create_clock -name clk27 -period 37.037 [get_nets {clk27}]          // 27 MHz
create_clock -name hclk -period 13.468 [get_nets {hclk}]            // 74.25 MHz pixel clock
create_clock -name hclk5 -period 2.6936 [get_nets {hclk5}]          // 371.25 MHz TMDS
create_clock -name clk12 -period 83.333 [get_nets {clk12}]          // 12 MHz USB

// The USB hosts' button levels reach sys_clk only through two-flop
// synchronisers (monitor_top.v).
set_clock_groups -asynchronous -group [get_clocks {clk12}] -group [get_clocks {sys_clk}]
