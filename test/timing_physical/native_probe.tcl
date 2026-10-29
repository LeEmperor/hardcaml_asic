# C-owned native invocation: first load the actual netlist+Liberty or ODB+Liberty.
# Set hc_physical_sdc to the unmodified emitted SDC and hc_physical_output to a
# fresh existing output directory. Retain enclosing command/process/library inputs.
# This script writes native observations; A does not execute it.
if {![info exists hc_physical_sdc] || ![info exists hc_physical_output]} {
    error "set hc_physical_sdc and hc_physical_output before sourcing native_probe.tcl"
}
foreach name {endpoints.tcl traces.tcl state.sdc downstream-min.rpt downstream-max.rpt} {
    if {[file exists [file join $hc_physical_output $name]]} { error "fresh native probe outputs required" }
}
read_sdc $hc_physical_sdc
set endpoints [::hc_pt7::checked_endpoints]
set traces [::hc_pt7::checked_traces]
set named_endpoints {}
dict for {id endpoint} $endpoints {
    foreach key {cell q data clock reset} {
        dict set endpoint $key [get_full_name [dict get $endpoint $key]]
    }
    dict set named_endpoints $id $endpoint
}
foreach {name value} [list endpoints.tcl $named_endpoints traces.tcl $traces] {
    set f [open [file join $hc_physical_output $name] {WRONLY CREAT EXCL}]
    puts $f [list set native_observation $value]
    close $f
}
write_sdc -no_timestamp -digits 12 [file join $hc_physical_output state.sdc]
foreach mode {min max} {
    set path [file join $hc_physical_output downstream-$mode.rpt]
    set f [open $path {WRONLY CREAT EXCL}]
    close $f
    dict for {id endpoint} $endpoints {
        if {[dict get $endpoint index] == 0} { continue }
        set previous {}
        dict for {other candidate} $endpoints {
            if {[dict get $candidate chain] eq [dict get $endpoint chain] &&
                [dict get $candidate index] == [dict get $endpoint index]-1} {
                lappend previous [dict get $candidate q]
            }
        }
        set q [::hc_pt7::one $previous "native predecessor for $id"]
        report_checks -from $q -to [dict get $endpoint data] -path_delay $mode -format full_clock_expanded -digits 6 >> $path
    }
}
puts "HC_PHYSICAL_NATIVE_PROBE_COMPLETE stages=[dict size $endpoints] traces=[llength $traces]"
# A marker alone is not acceptance: C must check nonempty paths, expected native
# effects, actual enclosing process completion and before/after sequential counts.
