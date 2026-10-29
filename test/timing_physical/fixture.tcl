# Extend the independent old API model; no EDA is claimed by this fixture.
proc all_registers {flag} {
    if {$flag ne "-cells"} { error "expected exact sequential cells" }
    set result $::stages
    if {$::case eq "extra_register"} { lappend result hidden_ff }
    if {$::case eq "missing_register"} { set result [lrange $result 1 end] }
    if {$::case eq "duplicate_register"} { lappend result rx0 }
    return $result
}
proc chain_to {sink root count master} {
    set upstream $root
    for {set i 0} {$i < $count} {incr i} {
        set next physical_$i
        add_buffer "physical$i" $upstream $next $master
        set upstream $next
    }
    dict set ::nets $sink $upstream
}
switch -- $case {
    interstage { chain_to rx1/D hc_pt7_rx0 1 sg13cmos5l_buf_2 }
    delay_interstage { chain_to rx1/D hc_pt7_rx0 1 sg13cmos5l_dlygate4sd1_1 }
    delay_clock { chain_to rx1/CLK clk_net 1 sg13cmos5l_dlygate4sd2_1 }
    delay_capture { chain_to rx0/D data_net 1 sg13cmos5l_dlygate4sd3_1 }
    delay_reset { chain_to rr1/RESET_B rst_net 1 sg13cmos5l_dlygate4sd1_1 }
    moved_anchor {
        dict set nets rx0/Q original_q
        add_buffer moved original_q hc_pt7_rx0 sg13cmos5l_dlygate4sd2_1
    }
    anchor_eight - anchor_nine {
        dict set nets rx0/Q original_q
        set count [expr {$case eq "anchor_eight" ? 8 : 9}]
        chain_to unused_sink original_q $count sg13cmos5l_buf_4
        set last "physical[expr {$count-1}]/X"
        dict set nets $last hc_pt7_rx0
    }
    buffer16 { chain_to rx1/D hc_pt7_rx0 1 sg13cmos5l_buf_16 }
    buffer8 { chain_to rx1/D hc_pt7_rx0 1 sg13cmos5l_buf_8 }
    buffer4 { chain_to rx1/D hc_pt7_rx0 1 sg13cmos5l_buf_4 }
    sized_flops {
        dict set masters rr0 sg13cmos5l_dfrbp_1
        dict set masters rr1 sg13cmos5l_dfrbp_2
        dict set masters rx0 sg13cmos5l_dfrbpq_1
        dict set masters rx1 sg13cmos5l_dfrbpq_2
    }
    wrong_predecessor { chain_to rx1/D hc_pt7_rr0 1 sg13cmos5l_buf_1 }
    interstage_inversion { chain_to rx1/D hc_pt7_rx0 1 sg13cmos5l_inv_1 }
    unknown_delay { chain_to rx1/D hc_pt7_rx0 1 sg13cmos5l_dlygate4sd4_1 }
    interstage_eight { chain_to rx1/D hc_pt7_rx0 8 sg13cmos5l_dlygate4sd3_1 }
    interstage_nine { chain_to rx1/D hc_pt7_rx0 9 sg13cmos5l_buf_1 }
    root_contention { add_buffer contention data_net hc_pt7_rx0 sg13cmos5l_buf_1 }
    input_contention { add_buffer contention ena_net data_net sg13cmos5l_buf_1 }
    q_input_contention { dict set nets ena hc_pt7_rx0 }
    shifted_input { chain_to rx0/D ena_net 1 sg13cmos5l_buf_1 }
    anchor_inversion {
        dict set nets rx0/Q original_q
        add_buffer moved original_q hc_pt7_rx0 sg13cmos5l_inv_1
    }
    merged_anchor { dict set nets rx1/Q unused_q; add_buffer moved hc_pt7_rx0 hc_pt7_rx1 sg13cmos5l_buf_1 }
}
