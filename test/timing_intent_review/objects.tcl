# Independent typed model, corrected against C's actual A-REAL-2 probe.
# Port -> top Pin -> Term -> internal Net; top Pin.net is always NULL.
set queried {}
set applied {}
set pins {}
set masters [dict create u0 sg13cmos5l_dfrbpq_1 u1 sg13cmos5l_dfrbpq_1]
set anchors {hc_pt7_review0 hc_pt7_review1}
set ports [list clk rst_n ena {ui_in[0]} {ui_in[1]}]
set directions [dict create]
foreach p $ports { dict set directions $p input }
set portnets [dict create clk clk_net rst_n reset_net ena ena_net {ui_in[0]} async_data {ui_in[1]} other_data]
set nets [dict create u0/Q hc_pt7_review0 u1/Q hc_pt7_review1 \
    u0/D async_data u1/D hc_pt7_review0 u0/CLK clk_net u1/CLK clk_net \
    u0/RESET_B reset_net u1/RESET_B reset_net]
foreach cell {u0 u1} { foreach pin {Q D CLK RESET_B} { lappend pins "$cell/$pin" } }
proc buffer {cell input output {master sg13cmos5l_buf_1}} {
    lappend ::pins "$cell/A" "$cell/X"
    dict set ::masters $cell $master
    dict set ::nets "$cell/A" $input
    dict set ::nets "$cell/X" $output
}
proc chain {sink source count {master sg13cmos5l_buf_1}} {
    set previous $source
    for {set i 0} {$i<$count} {incr i} {
        buffer "b$i" $previous "bn$i" $master
        set previous "bn$i"
    }
    dict set ::nets $sink $previous
}
switch -- $case {
    wrong_clock { dict set nets u1/CLK ena_net }
    wrong_capture_source { dict set nets u0/D ena_net }
    wrong_reset_source { dict set nets u1/RESET_B ena_net }
    wrong_interstage { dict set nets u1/D ena_net }
    missing_reset_pin { set pins [lsearch -all -inline -not -exact $pins u1/RESET_B] }
    disconnected_clock { dict unset nets u1/CLK }
    null_clock { dict set nets u1/CLK NULL }
    constant_clock { dict set nets u1/CLK constant_net }
    disconnected_capture { dict unset nets u0/D }
    disconnected_reset { dict unset nets u1/RESET_B }
    shorted_inputs { dict set portnets ena clk_net }
    source_internal_driver { buffer extra other_data async_data }
    buffered_clock { chain u1/CLK clk_net 1 }
    buffered_capture { chain u0/D async_data 1 }
    buffered_reset { chain u1/RESET_B reset_net 2 }
    eight_buffers { chain u0/D async_data 8 }
    nine_buffers { chain u0/D async_data 9 }
    inverted_clock { chain u1/CLK clk_net 1 sg13cmos5l_inv_1 }
    inverted_capture { chain u0/D async_data 1 sg13cmos5l_inv_1 }
    inverted_reset { chain u1/RESET_B reset_net 1 sg13cmos5l_inv_1 }
    unknown_logic { chain u0/D async_data 1 sg13cmos5l_and2_1 }
    wrong_buffer_root { chain u0/D ena_net 1 }
    multiple_drivers { chain u0/D async_data 1; buffer extra async_data bn0 }
    cycle { chain u0/D async_data 2; dict set nets b0/A bn1 }
    missing_buffer_A { chain u0/D async_data 1; dict unset nets b0/A }
    null_buffer_A { chain u0/D async_data 1; dict set nets b0/A NULL }
    multi_buffer_A { chain u0/D async_data 1 }
    wrong_buffer_output {
        chain u0/D async_data 1
        lappend pins b0/Y
        dict set nets b0/Y bn0
        dict unset nets b0/X
    }
    buffered_interstage { chain u1/D hc_pt7_review0 1 }
    top_output_source - top_output_buffer - top_output_anchor {
        set net async_data
        if {$case eq "top_output_buffer"} { chain u0/D async_data 1; set net bn0 }
        if {$case eq "top_output_anchor"} { set net hc_pt7_review0 }
        lappend ports {uo_out[0]}
        dict set directions {uo_out[0]} output
        dict set portnets {uo_out[0]} $net
    }
}
proc kind {object} { return [lindex [split $object :] 0] }
proc name {object} { return [string range $object [expr {[string first : $object]+1}] end] }
proc get_full_name {object} {
    if {[kind $object] ni {Port TopPin Pin Net Cell}} { error "stub: untyped object $object" }
    return [name $object]
}
# Native OpenSTA PatternMatch has only * and ? wildcards. Backslash and [] are
# literals. This independent recursive matcher does not delegate to Tcl glob.
proc native_match {pattern value} {
    set pi 0; set vi 0
    set pn [string length $pattern]; set vn [string length $value]
    while {$pi<$pn && $vi<$vn && ([string index $pattern $pi] eq [string index $value $vi] || [string index $pattern $pi] eq "?")} { incr pi; incr vi }
    if {$pi==$pn && $vi==$vn} { return 1 }
    if {$pi<$pn && [string index $pattern $pi] eq "*"} {
        if {$pi+1==$pn} { return 1 }
        for {} {$vi<=$vn} {incr vi} {
            if {[native_match [string range $pattern [expr {$pi+1}] end] [string range $value $vi end]]} { return 1 }
        }
    }
    return 0
}
proc query {names patterns type} {
    set result {}
    foreach pattern $patterns { foreach n $names { if {[native_match $pattern $n]} { lappend result "$type:$n" } } }
    return $result
}
proc get_ports {flag patterns} {
    lappend ::queried [list get_ports $flag $patterns]
    if {$flag ne "-quiet"} { error "stub: unexpected port query" }
    return [query $::ports $patterns Port]
}
namespace eval ::sta {}
proc ::sta::get_port_pin {port} {
    lappend ::queried [list port_to_pin $port]
    if {[kind $port] ne "Port" || [name $port] ni $::ports} { error "stub: adapter requires Port" }
    if {$::case eq "null_port_pin" && [name $port] eq {ui_in[0]}} { return NULL }
    if {$::case eq "empty_port_pin" && [name $port] eq {ui_in[0]}} { return {} }
    if {$::case eq "wrong_port_pin" && [name $port] eq {ui_in[0]}} { return TopPin:ena }
    return "TopPin:[name $port]"
}
proc top_pin_method {port method} {
    lappend ::queried [list top_pin $method $port]
    if {$method eq "net"} { return NULL }
    if {$method ne "term"} { error "stub: unsupported top Pin method" }
    if {$port eq {ui_in[0]}} {
        if {$::case eq "null_top_term"} { return NULL }
        if {$::case eq "empty_top_term"} { return {} }
        if {$::case eq "multiple_top_terms"} { return [list Term:clk Term:rst_n] }
    }
    return "Term:$port"
}
proc term_method {port method} {
    lappend ::queried [list term $method $port]
    if {$method ne "net"} { error "stub: unsupported Term method" }
    if {$port eq {ui_in[0]}} {
        if {$::case eq "null_term_net"} { return NULL }
        if {$::case eq "empty_term_net"} { return {} }
        if {$::case eq "multiple_term_nets"} { return {Net:async_data Net:other_data} }
    }
    if {![dict exists $::portnets $port]} { return NULL }
    return "Net:[dict get $::portnets $port]"
}
foreach p $ports {
    interp alias {} "TopPin:$p" {} top_pin_method $p
    interp alias {} "Term:$p" {} term_method $p
}
proc get_nets {flag object} {
    lappend ::queried [list get_nets $flag $object]
    if {$flag eq "-quiet"} { return [query $::anchors $object Net] }
    if {$flag ne "-of_objects" || [kind $object] ni {Pin TopPin}} { error "stub: get_nets requires Pin, never Port" }
    set n [name $object]
    if {[kind $object] eq "TopPin"} { return [list NULL] }
    set map $::nets
    if {$::case eq "multi_buffer_A" && $n eq "b0/A"} { return {Net:async_data Net:other_data} }
    if {![dict exists $map $n]} { return {} }
    set net [dict get $map $n]
    if {$net eq "NULL"} { return [list NULL] }
    return [list "Net:$net"]
}
proc get_pins {flag object} {
    lappend ::queried [list get_pins $flag $object]
    if {$flag eq "-quiet"} { return [query $::pins $object Pin] }
    if {$flag ne "-of_objects" || [kind $object] ne "Net"} { error "stub: get_pins requires Net" }
    set result {}; set net [name $object]
    foreach p $::pins { if {[dict exists $::nets $p] && [dict get $::nets $p] eq $net} { lappend result "Pin:$p" } }
    # Native net iteration includes top-level sink and source pins.
    foreach p $::ports { if {[dict exists $::portnets $p] && [dict get $::portnets $p] eq $net} { lappend result "TopPin:$p" } }
    return $result
}
proc get_cells {flag object} {
    lappend ::queried [list get_cells $flag $object]
    if {$flag ne "-of_objects" || [kind $object] ne "Pin"} { error "stub: get_cells requires internal Pin" }
    return [list "Cell:[lindex [split [name $object] /] 0]"]
}
proc get_property {object property} {
    lappend ::queried [list get_property $object $property]
    set n [name $object]
    if {$property eq "ref_name" && [kind $object] eq "Cell"} { return [dict get $::masters $n] }
    if {$property ne "direction"} { error "stub: unsupported property" }
    if {[kind $object] in {Port TopPin}} { return [dict get $::directions $n] }
    if {[kind $object] ne "Pin"} { error "stub: expected Pin for direction" }
    if {[lindex [split $n /] end] in {Q X Y}} { return output }
    return input
}
proc set_false_path {args} {
    if {[llength $args]!=4 || [kind [lindex $args 1]] ne "Port"} { error "stub: expected source Port" }
    foreach target [lindex $args 3] { if {[kind $target] ne "Pin"} { error "stub: expected target Pin" } }
    lappend ::applied $args
}
