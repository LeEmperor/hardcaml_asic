let contract = "hardcaml-asic.timing-native-coverage"
let profile = "opensta-2.7-native-state-v2"
let path = "constraints/pt7-native-coverage.tcl"
let manifest () =
  `Assoc ["contract", `String contract; "schema", `Int 2;
          "profile", `String profile; "producer", `String path]

let render () = {|# hardcaml-asic retained native-state producer, contract version 2.
# No path-effect or exhaustive per-check classification is inferred.
namespace eval ::hc_pt7_native {
  proc string_json {value} {
    if {[string bytelength $value] > 65536 || [string first \u0000 $value] >= 0} {
      error "PT7 native string budget exceeded/NUL"
    }
    set out {"}
    foreach char [split $value {}] {
      scan $char %c code
      if {$code == 34} { append out {\"} } elseif {$code == 92} {
        append out {\\}
      } elseif {$code < 32} { append out [format {\u%04x} $code] } else {
        append out $char
      }
    }
    append out {"}
    return $out
  }
  proc string_array {values} {
    set items {}
    foreach value $values { lappend items [string_json $value] }
    return "\[[join $items ,]\]"
  }
  proc diagnostic_string {value} {
    foreach line [split $value \n] {
      if {[regexp {^[ \t\r]*HC_ASIC_NATIVE_} $line]} {
        error "PT7 native diagnostic contains reserved marker line"
      }
    }
    return [string_json $value]
  }
  proc diagnostic_array {values} {
    set items {}
    foreach value $values { lappend items [diagnostic_string $value] }
    return "\[[join $items ,]\]"
  }
  proc output {path value} {
    set f [open $path w]
    fconfigure $f -encoding utf-8 -translation lf
    try { puts $f $value } finally { close $f }
  }
  proc write {directory} {
    if {![file isdirectory $directory]} { error "PT7 native output directory missing" }
    foreach name {native-state.sdc native-data.json native-checks.rpt native-endpoints.rpt} {
      if {[file exists [file join $directory $name]]} { error "PT7 native output already exists: $name" }
    }
    write_sdc -no_timestamp -digits 12 [file join $directory native-state.sdc]
    set checks [file join $directory native-checks.rpt]
    output $checks {HC_ASIC_NATIVE_CHECKS_V2 opensta-2.7-native-state-v2}
    set categories {}
    set records 0
    foreach {name switches} {
      no_input_delay          {1 0 0 0 0 0 0}
      no_output_delay         {0 1 0 0 0 0 0}
      multiple_clock          {0 0 1 0 0 0 0}
      no_clock                {0 0 0 1 0 0 0}
      unconstrained_endpoints {0 0 0 0 1 0 0}
      loops                   {0 0 0 0 0 1 0}
      generated_clocks        {0 0 0 0 0 0 1}
    } {
      set errors [sta::check_timing_cmd {*}$switches]
      set groups {}
      foreach group $errors {
        incr records [llength $group]
        if {[llength $group] == 0 || $records > 65536} { error "PT7 native group budget/shape" }
        set message [diagnostic_string [lindex $group 0]]
        set details [diagnostic_array [lrange $group 1 end]]
        lappend groups "\{\"message\":$message,\"details\":$details\}"
      }
      set count [llength $groups]
      lappend categories "\{\"name\":[string_json $name],\"group_count\":$count,\"groups\":\[[join $groups ,]\]\}"
      # Public native printer, independently checked against the structured groups.
      set f [open $checks a]
      puts $f "HC_ASIC_NATIVE_CATEGORY_BEGIN $name"
      close $f
      check_setup -verbose -$name >> $checks
      set f [open $checks a]
      puts $f "HC_ASIC_NATIVE_CATEGORY_END $name"
      close $f
    }
    set f [open $checks a]
    puts $f HC_ASIC_NATIVE_CHECKS_V2_COMPLETE
    close $f
    set endpoints {}
    foreach pin [sta::endpoints] {
      lappend endpoints [get_full_name $pin]
      if {[llength $endpoints] > 65536} { error "PT7 native endpoint budget exceeded" }
    }
    set endpoints [lsort -ascii -unique $endpoints]
    set endpoint_lines {}
    foreach endpoint $endpoints { lappend endpoint_lines [string_json $endpoint] }
    lappend endpoint_lines HC_ASIC_NATIVE_ENDPOINTS_COMPLETE
    output [file join $directory native-endpoints.rpt] [join $endpoint_lines \n]
    set data "\{\"schema\":2,\"contract\":\"hardcaml-asic.timing-native-coverage\",\"profile\":\"opensta-2.7-native-state-v2\",\"complete\":true,\"categories\":\[[join $categories ,]\],\"endpoint_count\":[llength $endpoints],\"endpoints\":[string_array $endpoints]\}"
    output [file join $directory native-data.json] $data
    foreach name {native-state.sdc native-data.json native-checks.rpt native-endpoints.rpt} {
      if {[file size [file join $directory $name]] > 8388608} { error "PT7 native file budget exceeded" }
    }
    puts HC_ASIC_NATIVE_V2_COMPLETE
  }
}
|}
