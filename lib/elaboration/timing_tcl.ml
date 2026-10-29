open! Core

(* These are literal Tcl list elements, not executable user text. Native query
   patterns only select candidates; literal full-name equality determines matches.
   In particular OpenSTA does not implement Tcl's bracket/backslash glob rules. *)
let word s =
  "\"" ^ String.concat_map s ~f:(function
    | '\\' -> "\\\\" | '"' -> "\\\"" | '$' -> "\\$" | '[' -> "\\["
    | ']' -> "\\]" | '\n' -> "\\n" | '\r' -> "\\r" | '\t' -> "\\t"
    | c -> String.of_char c) ^ "\""
;;

let helpers = {tcl|
# Generated exact scalar timing intent, scalar-q-driver-cmos5l-v1.
namespace eval ::hc_pt7 { variable top_port_names {} }
proc ::hc_pt7::fail {message} { error "hardcaml ASIC timing intent: $message" }
proc ::hc_pt7::json_string {s} {
    set result "\""
    foreach c [split $s ""] {
        scan $c %c code
        if {$code < 32 || $c eq "\\" || $c eq "\""} {
            append result [format {\u%04x} $code]
        } else { append result $c }
    }
    append result "\""
    return $result
}
proc ::hc_pt7::array_json {values} {
    set parts {}
    foreach v $values { lappend parts [json_string $v] }
    return "\[[join $parts ,]\]"
}
proc ::hc_pt7::emit {event fields} {
    puts "HC_ASIC_TIMING_V1\t\{\"schema_version\":1,\"event\":[json_string $event]$fields\}"
}
proc ::hc_pt7::one {objects label} {
    if {[llength $objects] != 1} { fail "$label: expected exactly one object, got [llength $objects]" }
    return [lindex $objects 0]
}
proc ::hc_pt7::exact {command name} {
    set matches {}
    foreach object [$command -quiet [list $name]] {
        if {[get_full_name $object] eq $name} { lappend matches $object }
    }
    return [one $matches "$command exact literal $name"]
}
proc ::hc_pt7::pin {cell name direction} {
    set p [exact get_pins "$cell/$name"]
    if {[get_property $p direction] ne $direction} { fail "wrong pin direction: $cell/$name" }
    return $p
}
proc ::hc_pt7::net {object label} {
    set connected [one [get_nets -of_objects $object] "$label net"]
    if {$connected eq "NULL"} { fail "$label: disconnected/null net" }
    return $connected
}
proc ::hc_pt7::port_net {port label} {
    # Top-instance Pin.net is the EXTERNAL side of the boundary (NULL on the
    # native top instance). Its Term.net is the connected INTERNAL design net.
    # Never guess by name, fall back to Pin.net or omit a failed root conversion.
    set pin [::sta::get_port_pin $port]
    if {$pin eq "NULL" || $pin eq ""} { fail "$label: input port has no scalar top pin" }
    if {[get_full_name $pin] ne [get_full_name $port]} { fail "$label: top pin differs from input port" }
    set term [one [$pin term] "$label top-pin Term"]
    if {$term eq "NULL"} { fail "$label: input top pin has no internal Term" }
    set connected [one [$term net] "$label internal Term net"]
    if {$connected eq "NULL"} { fail "$label: disconnected/null internal Term net" }
    return $connected
}
proc ::hc_pt7::outputs {net} {
    variable top_port_names
    set result {}
    foreach p [get_pins -of_objects $net] {
        # Native net pin iteration can include top-level output sink pins.
        # The checked TT interface has no slash-containing port names, so these
        # full names cannot alias a cell/pin path. They are not internal drivers.
        if {[get_full_name $p] in $top_port_names} { continue }
        if {[get_property $p direction] eq "output"} { lappend result $p }
    }
    return $result
}
proc ::hc_pt7::trace_input {sink source inputs label} {
    # Exactly noninverting wiring or <=8 known CMOS5L A->X buffers. No clock
    # inversion/gating, reset inversion, arbitrary fanin or constant fallback.
    set source_net [get_full_name [port_net $source "$label source"]]
    set current [net $sink $label]
    set seen {}
    set hops 0
    while {1} {
        set name [get_full_name $current]
        if {$name in $seen} { fail "$label: cyclic mapped source trace" }
        lappend seen $name
        set drivers [outputs $current]
        set ports {}
        if {[dict exists $inputs $name]} { set ports [dict get $inputs $name] }
        if {$name eq $source_net} {
            if {$ports ne [list [get_full_name $source]] || [llength $drivers] != 0} {
                fail "$label: ambiguous mapped input driver"
            }
            return
        }
        if {[llength $ports] != 0} { fail "$label: mapped source differs from declared input" }
        set driver [one $drivers "$label: unsupported/disconnected source driver"]
        if {$hops >= 8} { fail "$label: mapped source exceeds eight buffer hops" }
        set cell [one [get_cells -of_objects $driver] "$label buffer cell"]
        set cell_name [get_full_name $cell]
        set master [get_property $cell ref_name]
        if {$master ni {sg13cmos5l_buf_1 sg13cmos5l_buf_2 sg13cmos5l_buf_4 sg13cmos5l_buf_8 sg13cmos5l_buf_16}} {
            fail "$label: unsupported source transform $master; only noninverting CMOS5L buffers are supported"
        }
        set x [pin $cell_name X output]
        if {[get_full_name $driver] ne [get_full_name $x]} { fail "$label: source buffer driver is not X" }
        set a [pin $cell_name A input]
        set current [net $a "$label buffer A"]
        incr hops
    }
}
proc ::hc_pt7::run {stage_specs exception_specs} {
    variable top_port_names
    emit begin ",\"stage_count\":[llength $stage_specs],\"exception_count\":[llength $exception_specs]"
    set primary [exact get_ports clk]
    if {[get_property $primary direction] ne "input"} { fail "primary clk is not input" }
    # Native get_ports expands bus members to scalar Ports. Use the SAME checked
    # internal-Term conversion for root caching and exception/clock source traces.
    set inputs [dict create]
    set top_port_names {}
    foreach port [get_ports -quiet *] {
        lappend top_port_names [get_full_name $port]
        if {[get_property $port direction] ne "input"} { continue }
        set internal [port_net $port "input root [get_full_name $port]"]
        dict lappend inputs [get_full_name $internal] [get_full_name $port]
    }
    set stages [dict create]
    set cells {}
    foreach spec $stage_specs {
        lassign $spec id anchor has_async chain index
        set net [exact get_nets $anchor]
        # A combinational driver, buffer or inverted Q is not a register anchor.
        set qp [one [outputs $net] "Q driver for $id"]
        set cell [one [get_cells -of_objects $qp] "driver cell for $id"]
        set cell_name [get_full_name $cell]
        set master [get_property $cell ref_name]
        if {$master ni {sg13cmos5l_dfrbpq_1 sg13cmos5l_dfrbpq_2 sg13cmos5l_dfrbp_1 sg13cmos5l_dfrbp_2}} {
            fail "unsupported mapped master $master for $id"
        }
        set q [pin $cell_name Q output]
        if {[get_full_name $q] ne [get_full_name $qp]} { fail "anchor is not noninverting Q for $id" }
        if {$cell_name in $cells} { fail "merged timing stage cell $cell_name" }
        lappend cells $cell_name
        set d [pin $cell_name D input]
        set clk [pin $cell_name CLK input]
        set reset [pin $cell_name RESET_B input]
        trace_input $clk $primary $inputs "mapped clock for $id"
        set async_name {}
        if {$has_async} { set async_name [get_full_name $reset] }
        dict set stages $id [list $d $reset $has_async $q $chain $index]
        set async_json null
        if {$has_async} { set async_json [json_string $async_name] }
        emit stage ",\"id\":[json_string $id],\"anchor\":[json_string $anchor],\"cell\":[json_string $cell_name],\"master\":[json_string $master],\"q_pin\":[json_string [get_full_name $q]],\"data_pin\":[json_string [get_full_name $d]],\"async_pin\":$async_json"
    }
    # Verify the declared simple interstage data topology survived mapping.
    dict for {id stage} $stages {
        lassign $stage d reset has_async q chain index
        if {$index == 0} { continue }
        set previous {}
        dict for {other other_stage} $stages {
            lassign $other_stage od or oh oq oc oi
            if {$oc eq $chain && $oi == $index-1} { lappend previous $oq }
        }
        set previous [one $previous "previous stage for $id"]
        set qnet [one [get_nets -of_objects $previous] "previous Q net for $id"]
        set dnet [one [get_nets -of_objects $d] "data net for $id"]
        if {[get_full_name $qnet] ne [get_full_name $dnet]} { fail "mapped interstage data differs for $id" }
    }
    set resolved {}
    foreach spec $exception_specs {
        lassign $spec id kind source_name targets
        set source [exact get_ports $source_name]
        if {[get_property $source direction] ne "input"} { fail "source is not input: $source_name" }
        set pins {}
        set names {}
        foreach target $targets {
            if {![dict exists $stages $target]} { fail "unknown stage $target" }
            lassign [dict get $stages $target] d reset has_async q chain index
            if {$kind eq "async_capture"} {
                if {$index != 0 || [llength $targets] != 1} { fail "capture is not one first stage" }
                set p $d
                trace_input $p $source $inputs "mapped capture source for $target"
            } elseif {$kind eq "async_reset"} {
                if {!$has_async} { fail "stage lacks asynchronous control: $target" }
                set p $reset
                trace_input $p $source $inputs "mapped active-low reset source for $target"
            } else { fail "unknown exception kind $kind" }
            set name [get_full_name $p]
            if {$name in $names} { fail "duplicate resolved exception target $name" }
            lappend pins $p
            lappend names $name
        }
        if {[llength $pins] == 0} { fail "empty exception target list" }
        set fields ",\"id\":[json_string $id],\"kind\":[json_string $kind],\"source\":[json_string $source_name],\"targets\":[array_json $names]"
        emit resolved $fields
        lappend resolved [list $source $pins $fields]
    }
    emit validated ",\"stage_count\":[llength $stage_specs],\"exception_count\":[llength $exception_specs]"
    foreach entry $resolved {
        lassign $entry source pins fields
        set_false_path -from $source -to $pins
        emit applied $fields
    }
    emit complete ",\"stage_count\":[llength $stage_specs],\"exception_count\":[llength $exception_specs]"
}
|tcl}

(* V1 above is deliberately frozen: old bundles retain byte-for-byte rendering.
   V2 shares only primitive queries/JSON; its graph and publication contract is
   explicit, and does not reinterpret the historical direct-interstage policy. *)
let physical_helpers = {tcl|
# scalar-q-driver-cmos5l-physical-v2; all registers must be declared stages.
namespace eval ::hc_pt7 {
    variable endpoint_map {}
    variable traces {}
    variable checked 0
}
proc ::hc_pt7::checked_endpoints {} {
    variable checked; variable endpoint_map
    if {!$checked} { fail "physical endpoint map is not checked" }
    return $endpoint_map
}
proc ::hc_pt7::checked_traces {} {
    variable checked; variable traces
    if {!$checked} { fail "physical trace inventory is not checked" }
    return $traces
}
proc ::hc_pt7::physical_hop {driver label} {
    set cell [one [get_cells -of_objects $driver] "$label transform cell"]
    set name [get_full_name $cell]
    set master [get_property $cell ref_name]
    if {$master ni {sg13cmos5l_buf_1 sg13cmos5l_buf_2 sg13cmos5l_buf_4 sg13cmos5l_buf_8 sg13cmos5l_buf_16 sg13cmos5l_dlygate4sd1_1 sg13cmos5l_dlygate4sd2_1 sg13cmos5l_dlygate4sd3_1}} {
        fail "$label: unqualified noninverting transform $master"
    }
    set x [pin $name X output]
    if {[get_full_name $driver] ne [get_full_name $x]} { fail "$label: transform driver is not X" }
    return [dict create cell $name master $master input [get_full_name [pin $name A input]] output [get_full_name $x]]
}
proc ::hc_pt7::record_trace {label root sink nets hops} {
    variable traces
    set trace [dict create label $label root $root sink $sink nets $nets hops $hops]
    lappend traces $trace
    set json_hops {}
    foreach hop $hops {
        set fields {}
        dict for {key value} $hop { lappend fields "[json_string $key]:[json_string $value]" }
        lappend json_hops "\{[join $fields ,]\}"
    }
    emit trace ",\"label\":[json_string $label],\"root\":[json_string $root],\"sink\":[json_string $sink],\"nets\":[array_json $nets],\"hops\":\[[join $json_hops ,]\]"
}
proc ::hc_pt7::walk {current root kind inputs label sink} {
    # root kind: port, Q, or anchor (discover a supported flop Q).
    set seen {}; set hops {}
    while {1} {
        set name [get_full_name $current]
        if {$name in $seen} { fail "$label: cyclic physical trace" }
        lappend seen $name
        set ports {}
        if {[dict exists $inputs $name]} { set ports [dict get $inputs $name] }
        set drivers [outputs $current]
        if {$kind eq "port" && $name eq [get_full_name [port_net $root "$label root"]]} {
            if {$ports ne [list [get_full_name $root]] || [llength $drivers] != 0} {
                fail "$label: ambiguous physical input driver"
            }
            record_trace $label [get_full_name $root] $sink $seen $hops
            return $root
        }
        if {[llength $ports] != 0} { fail "$label: wrong/contending input driver" }
        set driver [one $drivers "$label physical driver"]
        if {$kind eq "Q" && [get_full_name $driver] eq [get_full_name $root]} {
            record_trace $label [get_full_name $root] $sink $seen $hops
            return $root
        }
        if {$kind eq "anchor"} {
            set cell [one [get_cells -of_objects $driver] "$label Q cell"]
            set master [get_property $cell ref_name]
            if {$master in {sg13cmos5l_dfrbpq_1 sg13cmos5l_dfrbpq_2 sg13cmos5l_dfrbp_1 sg13cmos5l_dfrbp_2}} {
                set q [pin [get_full_name $cell] Q output]
                if {[get_full_name $driver] ne [get_full_name $q]} { fail "$label: anchor is not noninverting Q" }
                record_trace $label [get_full_name $q] $sink $seen $hops
                return $q
            }
        }
        if {[llength $hops] >= 8} { fail "$label: physical trace exceeds eight buffer hops" }
        set hop [physical_hop $driver $label]
        lappend hops $hop
        set current [net [exact get_pins [dict get $hop input]] "$label transform input"]
    }
}
proc ::hc_pt7::run {stage_specs exception_specs} {
    variable top_port_names; variable endpoint_map; variable traces; variable checked
    set checked 0; set endpoint_map {}; set traces {}
    emit begin ",\"stage_count\":[llength $stage_specs],\"exception_count\":[llength $exception_specs]"
    set primary [exact get_ports clk]
    if {[get_property $primary direction] ne "input"} { fail "primary clk is not input" }
    set inputs [dict create]; set top_port_names {}
    foreach port [get_ports -quiet *] {
        lappend top_port_names [get_full_name $port]
        if {[get_property $port direction] eq "input"} {
            dict lappend inputs [get_full_name [port_net $port "input root"]] [get_full_name $port]
        }
    }
    set stages [dict create]; set cells {}
    foreach spec $stage_specs {
        lassign $spec id anchor has_async chain index
        set q [walk [exact get_nets $anchor] {} anchor $inputs "anchor for $id" $anchor]
        set cell [one [get_cells -of_objects $q] "stage cell for $id"]
        set name [get_full_name $cell]
        if {$name in $cells} { fail "merged timing stage cell $name" }
        lappend cells $name
        set master [get_property $cell ref_name]
        set d [pin $name D input]; set clk [pin $name CLK input]; set reset [pin $name RESET_B input]
        walk [net $clk "clock for $id"] $primary port $inputs "clock for $id" [get_full_name $clk]
        dict set stages $id [list $d $reset $has_async $q $chain $index]
        dict set endpoint_map $id [dict create cell $cell q $q data $d clock $clk reset $reset anchor $anchor master $master chain $chain index $index]
        set async_json null
        if {$has_async} { set async_json [json_string [get_full_name $reset]] }
        emit stage ",\"id\":[json_string $id],\"anchor\":[json_string $anchor],\"cell\":[json_string $name],\"master\":[json_string $master],\"q_pin\":[json_string [get_full_name $q]],\"data_pin\":[json_string [get_full_name $d]],\"async_pin\":$async_json"
    }
    # No unregistered sequential state, including clones or hidden inserted flops.
    set actual {}
    foreach cell [all_registers -cells] { lappend actual [get_full_name $cell] }
    if {[lsort -ascii $actual] ne [lsort -ascii $cells]} { fail "physical sequential inventory differs from exact declared stages" }
    emit inventory ",\"cells\":[array_json [lsort -ascii $cells]]"
    dict for {id stage} $stages {
        lassign $stage d reset has_async q chain index
        if {$index == 0} { continue }
        set previous {}
        dict for {other other_stage} $stages {
            lassign $other_stage od or oh oq oc oi
            if {$oc eq $chain && $oi == $index-1} { lappend previous $oq }
        }
        walk [net $d "data for $id"] [one $previous "previous stage for $id"] Q $inputs "interstage for $id" [get_full_name $d]
    }
    set resolved {}
    foreach spec $exception_specs {
        lassign $spec id kind source_name targets
        set source [exact get_ports $source_name]
        if {[get_property $source direction] ne "input"} { fail "source is not input: $source_name" }
        set pins {}; set names {}
        foreach target $targets {
            if {![dict exists $stages $target]} { fail "unknown stage $target" }
            lassign [dict get $stages $target] d reset has_async q chain index
            if {$kind eq "async_capture"} {
                if {$index != 0 || [llength $targets] != 1} { fail "capture is not one first stage" }
                set p $d
            } elseif {$kind eq "async_reset"} {
                if {!$has_async} { fail "stage lacks asynchronous control: $target" }
                set p $reset
            } else { fail "unknown exception kind $kind" }
            set name [get_full_name $p]
            walk [net $p "$kind for $target"] $source port $inputs "$kind for $target" $name
            if {$name in $names} { fail "duplicate resolved exception target $name" }
            lappend pins $p; lappend names $name
        }
        if {[llength $pins] == 0} { fail "empty exception target list" }
        set fields ",\"id\":[json_string $id],\"kind\":[json_string $kind],\"source\":[json_string $source_name],\"targets\":[array_json $names]"
        emit resolved $fields
        lappend resolved [list $source $pins $fields]
    }
    emit validated ",\"stage_count\":[llength $stage_specs],\"exception_count\":[llength $exception_specs]"
    foreach entry $resolved {
        lassign $entry source pins fields
        set_false_path -from $source -to $pins
        emit applied $fields
    }
    emit complete ",\"stage_count\":[llength $stage_specs],\"exception_count\":[llength $exception_specs]"
    set checked 1
}
|tcl}

let render_internal ~physical ~stages ~exceptions =
  let stage_specs = List.map stages ~f:(fun ((s : Platform.Timing.Stage.t), anchor, has_async) ->
    Printf.sprintf "[list %s %s %d %s %d]" (word s.id) (word anchor)
      (if has_async then 1 else 0) (word s.chain) s.index) in
  let exception_specs = List.map exceptions ~f:(fun (e : Platform.Timing.Exception.t) ->
    let source = match e.source.bit with None -> e.source.port
      | Some bit -> Printf.sprintf "%s[%d]" e.source.port bit in
    let targets = List.sort e.targets ~compare:(fun a b -> String.compare a.id b.id)
      |> List.map ~f:(fun s -> word s.id) |> String.concat ~sep:" " in
    Printf.sprintf "[list %s %s %s [list %s]]" (word e.id)
      (word (Platform.Timing.Exception.kind_string e.kind)) (word source) targets) in
  helpers ^ (if physical then physical_helpers else "") ^ Printf.sprintf "\n::hc_pt7::run [list %s] [list %s]\n"
     (String.concat ~sep:" " stage_specs) (String.concat ~sep:" " exception_specs)

let render ~stages ~exceptions = render_internal ~physical:false ~stages ~exceptions
let render_physical ~stages ~exceptions = render_internal ~physical:true ~stages ~exceptions
