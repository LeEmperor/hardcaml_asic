current_design tt_um_pt7_timing
create_clock -name clk -period 20.000000000000 [get_ports {clk}]
set_clock_transition 0.150000005960 [get_clocks {clk}]
set_clock_uncertainty 0.250000000000 clk
set_input_delay 0.000000000000 -clock [get_clocks {clk}] -min -add_delay [get_ports {ui_in[0]}]
set_input_delay 1.000000000000 -clock [get_clocks {clk}] -max -add_delay [get_ports {ui_in[0]}]
set_output_delay 0.000000000000 -clock [get_clocks {clk}] -min -add_delay [get_ports {uo_out[0]}]
set_output_delay 2.000000000000 -clock [get_clocks {clk}] -max -add_delay [get_ports {uo_out[0]}]
set_false_path\
    -from [get_ports {ena}]\
    -to [get_pins {_4_/D}]
set_false_path\
    -from [get_ports {rst_n}]\
    -to [list [get_pins {_2_/RESET_B}]\
           [get_pins {_3_/RESET_B}]\
           [get_pins {_4_/RESET_B}]\
           [get_pins {_5_/RESET_B}]\
           [get_pins {_6_/RESET_B}]]
set_load -pin_load 0.006000000052 [get_ports {uo_out[0]}]
set_driving_cell -lib_cell sg13cmos5l_buf_4 -pin {X} -input_transition_rise 0.000000000000 -input_transition_fall 0.000000000000 [get_ports {ena}]
set_timing_derate -early 0.949999988079
set_timing_derate -late 1.049999952316
set_max_fanout 10.000000000000 [current_design]
