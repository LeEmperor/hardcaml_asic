# Explicit synthetic linked graph. The matcher models OpenSTA's * and ? native
# wildcards, with literal brackets/backslashes, NOT Tcl's bracket-class globbing.
set applied_count 0
set external_net_reads 0
set stages {rr0 rr1 rx0 rx1}
set ports [list clk rst_n ena {ui_in[0]} {ui_in[1]}]
set anchors {hc_pt7_rr0 hc_pt7_rr1 hc_pt7_rx0 hc_pt7_rx1}
set nets [dict create clk clk_net rst_n rst_net ena ena_net \
    {ui_in[0]} data_net {ui_in[1]} other_data_net]
set pins {}
set masters [dict create]
foreach s $stages {
    foreach pin {Q D CLK RESET_B} { lappend pins "$s/$pin" }
    dict set masters $s sg13cmos5l_dfrbpq_1
    dict set nets "$s/Q" "hc_pt7_$s"
    dict set nets "$s/CLK" clk_net
    dict set nets "$s/RESET_B" rst_net
}
dict set nets rr0/D one_net
dict set nets rr1/D hc_pt7_rr0
dict set nets rx0/D data_net
dict set nets rx1/D hc_pt7_rx0

# Native review repros isolate the changed connection while preserving names,
# mapped master/roles, source port presence and the remaining graph.
switch -- $case {
    top_output_sink { lappend ports {uo_out[0]}; dict set nets {uo_out[0]} data_net }
    q_output_sink { lappend ports {uo_out[0]}; dict set nets {uo_out[0]} hc_pt7_rx0 }
    wrong_clock { dict set nets rx1/CLK ena_net }
    disconnected_clock { dict unset nets rx1/CLK }
    null_clock { dict set nets rx1/CLK NULL }
    constant_clock { dict set nets rx1/CLK constant_net }
    wrong_capture_source { dict set nets rx0/D ena_net }
    disconnected_capture { dict unset nets rx0/D }
    null_capture { dict set nets rx0/D NULL }
    wrong_reset_source { dict set nets rr1/RESET_B ena_net }
    disconnected_reset { dict unset nets rr1/RESET_B }
    null_reset { dict set nets rr1/RESET_B NULL }
    wrong_data_net { dict set nets rx1/D wrong_net }
    shorted_inputs { dict set nets ena clk_net }
    wrong_source_direction { }
    late_missing_port { set ports [lsearch -all -inline -not -exact $ports rst_n] }
    missing_reset_pin { set pins [lsearch -all -inline -not -exact $pins rr1/RESET_B] }
}

proc add_buffer {cell input output master} {
    lappend ::pins "$cell/A" "$cell/X"
    dict set ::masters $cell $master
    dict set ::nets "$cell/A" $input
    dict set ::nets "$cell/X" $output
}
if {$case in {buffered_clock buffered_capture buffered_reset inverted_clock inverted_capture inverted_reset unknown_transform wrong_buffer_pin multi_driver buffer_cycle eight_buffers nine_buffers}} {
    set sink rx0/D
    set upstream data_net
    if {$case in {buffered_clock inverted_clock}} { set sink rx1/CLK; set upstream clk_net }
    if {$case in {buffered_reset inverted_reset}} { set sink rr1/RESET_B; set upstream rst_net }
    set count 1
    if {$case eq "eight_buffers"} { set count 8 }
    if {$case eq "nine_buffers"} { set count 9 }
    set master sg13cmos5l_buf_1
    if {$case in {inverted_clock inverted_capture inverted_reset}} { set master sg13cmos5l_inv_1 }
    if {$case eq "unknown_transform"} { set master sg13cmos5l_and2_1 }
    for {set i 0} {$i < $count} {incr i} {
        set next "trace_$i"
        add_buffer "buf$i" $upstream $next $master
        set upstream $next
    }
    dict set nets $sink $upstream
    if {$case eq "multi_driver"} { add_buffer extra data_net $upstream sg13cmos5l_buf_2 }
    if {$case eq "buffer_cycle"} {
        add_buffer loop trace_0 cycle_net sg13cmos5l_buf_1
        dict set nets buf0/A cycle_net
    }
    if {$case eq "wrong_buffer_pin"} {
        lappend pins buf0/Y
        dict set nets buf0/Y trace_0
        dict unset nets buf0/X
    }
}
if {$case eq "constant_reset"} {
    add_buffer tie {} constant_net sg13cmos5l_tiehi
    dict set nets rr1/RESET_B constant_net
}

proc matches {pattern name} {
    # Translate only the literal characters which Tcl's matcher interprets beyond
    # the two wildcard characters recognized by native OpenSTA PatternMatch.
    return [string match [string map [list \\ \\\\ \[ \\\[ \] \\\]] $pattern] $name]
}
proc query {objects patterns} {
    set result {}
    foreach pattern $patterns {
        foreach object $objects { if {[matches $pattern $object]} { lappend result $object } }
    }
    return $result
}
proc get_full_name {object} {
    if {[string match PORTPIN:* $object]} { return [string range $object 8 end] }
    return $object
}
proc get_ports {flag patterns} { return [query $::ports $patterns] }
namespace eval ::sta {}
proc ::sta::get_port_pin {port} {
    if {$port ni $::ports} { error "fixture: expected Port object" }
    if {$port eq "clk" && $::case eq "null_top_pin"} { return NULL }
    if {$port eq "clk" && $::case eq "wrong_top_pin"} { return PORTPIN:ena }
    return "PORTPIN:$port"
}
proc top_pin_method {port method} {
    if {$method eq "net"} { incr ::external_net_reads; return NULL }
    if {$method ne "term"} { error "fixture: unsupported top Pin method $method" }
    if {$port eq "clk" && $::case eq "null_top_term"} { return NULL }
    if {$port eq "clk" && $::case eq "empty_top_term"} { return {} }
    if {$port eq "clk" && $::case eq "multiple_top_terms"} { return {TERM:clk TERM:ena} }
    return "TERM:$port"
}
proc term_method {port method} {
    if {$method ne "net"} { error "fixture: unsupported Term method $method" }
    if {$port eq "clk" && $::case eq "null_internal_net"} { return NULL }
    if {$port eq "clk" && $::case eq "empty_internal_net"} { return {} }
    if {$port eq "clk" && $::case eq "multiple_internal_nets"} { return {clk_net ena_net} }
    if {[dict exists $::nets $port]} { return [dict get $::nets $port] }
    return NULL
}
foreach port $ports {
    interp alias {} "PORTPIN:$port" {} top_pin_method $port
    interp alias {} "TERM:$port" {} term_method $port
}
proc get_nets {flag value} {
    if {$flag eq "-quiet"} {
        if {$::case eq "empty_anchor" && $value eq "hc_pt7_rx1"} { return {} }
        if {$::case eq "ambiguous_anchor" && $value eq "hc_pt7_rx1"} { return {hc_pt7_rx1 hc_pt7_rx1} }
        if {$::case eq "nonexact_anchor" && $value eq "hc_pt7_rx1"} { return hc_pt7_rx1_extra }
        return [query $::anchors $value]
    }
    if {$value in $::ports} { error "fixture: native get_nets does not accept Port objects" }
    if {[string match PORTPIN:* $value]} { return [list [$value net]] }
    if {[dict exists $::nets $value]} { return [list [dict get $::nets $value]] }
    return {}
}
proc get_pins {flag value} {
    if {$flag eq "-quiet"} { return [query $::pins $value] }
    if {$::case eq "ambiguous_driver" && $value eq "hc_pt7_rx1"} { return {rx1/Q other/Q} }
    if {$::case eq "empty_driver" && $value eq "hc_pt7_rx1"} { return {} }
    if {$::case eq "inverted_q" && $value eq "hc_pt7_rx1"} { return {rx1/Q_N} }
    set result {}
    foreach p $::pins {
        if {[dict exists $::nets $p] && [dict get $::nets $p] eq $value} { lappend result $p }
    }
    # A top-level output's direction is output, but it is a sink on its net.
    if {$::case eq "top_output_sink" && $value eq "data_net"} { lappend result {uo_out[0]} }
    if {$::case eq "q_output_sink" && $value eq "hc_pt7_rx0"} { lappend result {uo_out[0]} }
    return $result
}
proc get_cells {flag value} {
    set cell [lindex [split $value /] 0]
    if {$::case eq "merged" && $cell eq "rx1"} { return rx0 }
    return [list $cell]
}
proc get_property {object property} {
    if {$property eq "ref_name"} {
        if {$::case eq "unknown_master" && $object eq "rx1"} { return combinational_buffer }
        if {$::case eq "dual_q_master" && $object in $::stages} { return sg13cmos5l_dfrbp_2 }
        return [dict get $::masters $object]
    }
    if {$object in $::ports} {
        if {$object eq {uo_out[0]}} { return output }
        if {$::case eq "wrong_source_direction" && $object eq {ui_in[0]}} { return output }
        return input
    }
    set pin [lindex [split $object /] 1]
    if {$::case eq "wrong_pin_direction" && $object eq "rr1/RESET_B"} { return output }
    if {$pin in {Q Q_N X Y}} { return output }
    return input
}
proc set_false_path {args} {
    incr ::applied_count
    if {$::case eq "apply_failure" && $::applied_count == 2} { error "fixture rejected second application" }
}
