# Independently implemented, inert scalar native-API graph model. No EDA.
set registers {rr0 rr1 rx0 rx1}
set ports {clk rst_n ena {ui_in[0]} {ui_in[1]} out}
set input_ports {clk rst_n ena {ui_in[0]} {ui_in[1]}}
set net_names {nclk nrst nena ndata nother hc_pt7_rr0 hc_pt7_rr1 hc_pt7_rx0 hc_pt7_rx1}
set connections [dict create clk nclk rst_n nrst ena nena {ui_in[0]} ndata {ui_in[1]} nother out hc_pt7_rx1]
set owners [dict create]; set directions [dict create]; set masters [dict create]
foreach cell $registers {
    dict set masters $cell sg13cmos5l_dfrbpq_1
    foreach role {Q D CLK RESET_B} {
        dict set owners $cell/$role $cell
        dict set directions $cell/$role [expr {$role eq "Q" ? "output" : "input"}]
    }
    dict set connections $cell/Q hc_pt7_$cell
    dict set connections $cell/CLK nclk
    dict set connections $cell/RESET_B nrst
}
dict set connections rr0/D nena
dict set connections rr1/D hc_pt7_rr0
dict set connections rx0/D ndata
dict set connections rx1/D hc_pt7_rx0
set apply_attempts 0; set apply_successes 0; set reject_application 0
set map_during_apply {}; set applied_scopes {}

proc get_full_name {object} {
    if {[string match PORT:* $object]} { return [string range $object 5 end] }
    return $object
}
proc get_ports {quiet names} {
    if {$names eq "*"} {return $::ports}
    set result {}
    foreach name $names {if {$name in $::ports} {lappend result $name}}
    return $result
}
proc get_nets {mode object} {
    if {$mode eq "-quiet"} {
        set result {}
        foreach name $object {foreach candidate $::net_names {if {$candidate eq $name} {lappend result $candidate}}}
        return $result
    }
    if {[dict exists $::connections $object]} {return [list [dict get $::connections $object]]}
    return {}
}
proc get_pins {mode object} {
    if {$mode eq "-quiet"} {
        set result {}
        foreach name $object {if {[dict exists $::directions $name]} {lappend result $name}}
        return $result
    }
    set result {}
    dict for {pin net} $::connections {
        if {$net eq $object && ([dict exists $::directions $pin] || $pin in $::ports)} {lappend result $pin}
    }
    return $result
}
proc get_cells {flag pin} {
    if {[dict exists $::owners $pin]} {return [list [dict get $::owners $pin]]}
    return {}
}
proc get_property {object property} {
    if {$property eq "ref_name"} {return [dict get $::masters $object]}
    if {$object in $::input_ports} {return input}
    if {$object in $::ports} {return output}
    return [dict get $::directions $object]
}
namespace eval sta {}
proc sta::get_port_pin {port} {return PORT:$port}
proc port_method {port method} {
    if {$method ne "term"} {error "external Pin.net must never be used"}
    return TERM:$port
}
proc term_method {port method} {
    if {$method ne "net"} {error "only internal Term.net is supported"}
    return [dict get $::connections $port]
}
foreach port $ports {
    interp alias {} PORT:$port {} port_method $port
    interp alias {} TERM:$port {} term_method $port
}
proc all_registers {option} {
    if {$option ne "-cells"} {error "wrong inventory option"}
    return $::registers
}
proc set_false_path {args} {
    incr ::apply_attempts
    lappend ::map_during_apply [catch {::hc_pt7::checked_endpoints}]
    puts "REVIEW_APPLY\t$::apply_attempts"
    if {$::reject_application == $::apply_attempts} {error "independent rejected application"}
    incr ::apply_successes
    lappend ::applied_scopes $args
}
proc buffer {cell from to {master sg13cmos5l_buf_1}} {
    dict set ::masters $cell $master
    foreach {pin direction net} [list A input $from X output $to] {
        dict set ::owners $cell/$pin $cell
        dict set ::directions $cell/$pin $direction
        dict set ::connections $cell/$pin $net
    }
    foreach net [list $from $to] {if {$net ni $::net_names} {lappend ::net_names $net}}
}
proc chain {prefix source sink count {master sg13cmos5l_buf_1}} {
    set current $source
    for {set i 0} {$i<$count} {incr i} {
        set next ${prefix}_net_$i
        buffer ${prefix}_$i $current $next $master
        set current $next
    }
    dict set ::connections $sink $current
}
