(* Tcl is bundle data, not a host-side EDA invocation. Geometry procedures are
   separate from the OpenDB adapter so synthetic integer-geometry tests exercise
   the same candidate search and validation as the emitted runtime. *)
let geometry = {tcl|# Generated CMOS5L exact256x16 R0 physical policy, version 1.
# No absolute contact coordinates: pins, obstructions and stripes come from ODB.
namespace eval ::hc_pdn { variable instances {}; variable dbu; variable clearance; variable neck; variable overlap; variable grid }

proc ::hc_pdn::fail {message} { error "hardcaml ASIC macro power: $message" }
proc ::hc_pdn::rect {box} {
    return [list [$box xMin] [$box yMin] [$box xMax] [$box yMax]]
}
proc ::hc_pdn::valid {r} {
    if {[llength $r] != 4} { return 0 }
    lassign $r x0 y0 x1 y1
    foreach v $r { if {![string is integer -strict $v]} { return 0 } }
    return [expr {$x0 < $x1 && $y0 < $y1}]
}
proc ::hc_pdn::inside {r bounds} {
    lassign $r x0 y0 x1 y1
    lassign $bounds bx0 by0 bx1 by1
    return [expr {$x0 >= $bx0 && $y0 >= $by0 && $x1 <= $bx1 && $y1 <= $by1}]
}
proc ::hc_pdn::expand {r margin} {
    lassign $r x0 y0 x1 y1
    return [list [expr {$x0-$margin}] [expr {$y0-$margin}] [expr {$x1+$margin}] [expr {$y1+$margin}]]
}
proc ::hc_pdn::translate {r x y} {
    lassign $r x0 y0 x1 y1
    return [list [expr {$x+$x0}] [expr {$y+$y0}] [expr {$x+$x1}] [expr {$y+$y1}]]
}
proc ::hc_pdn::intersection {a b} {
    lassign $a ax0 ay0 ax1 ay1
    lassign $b bx0 by0 bx1 by1
    set r [list [expr {max($ax0,$bx0)}] [expr {max($ay0,$by0)}] [expr {min($ax1,$bx1)}] [expr {min($ay1,$by1)}]]
    if {[valid $r]} { return $r }
    return {}
}
proc ::hc_pdn::clear {a b distance} {
    lassign $a ax0 ay0 ax1 ay1
    lassign $b bx0 by0 bx1 by1
    # Conservative rectangular clearance, including corner-to-corner cases.
    return [expr {$ax1+$distance <= $bx0 || $bx1+$distance <= $ax0 ||
                  $ay1+$distance <= $by0 || $by1+$distance <= $ay0}]
}
proc ::hc_pdn::contact {a b width height} {
    set r [intersection $a $b]
    if {$r eq {}} { return 0 }
    lassign $r x0 y0 x1 y1
    return [expr {$x1-$x0 >= $width && $y1-$y0 >= $height}]
}
proc ::hc_pdn::snap_up {x} {
    variable grid
    return [expr {int(ceil(double($x)/$grid))*$grid}]
}
proc ::hc_pdn::snap_down {x} {
    variable grid
    return [expr {int(floor(double($x)/$grid))*$grid}]
}
proc ::hc_pdn::legal {r net blockers bounds} {
    variable clearance
    variable grid
    if {![valid $r] || ![inside $r $bounds]} { return 0 }
    foreach v $r { if {$v % $grid != 0} { return 0 } }
    foreach b $blockers {
        lassign $b other br kind
        if {$other eq $net && $kind ne "obs"} { continue }
        if {![clear $r $br $clearance]} { return 0 }
    }
    return 1
}
proc ::hc_pdn::measured_clearance {rects net blockers} {
    set minimum {}
    foreach r $rects {
        lassign $r ax0 ay0 ax1 ay1
        foreach b $blockers {
            lassign $b other br kind
            if {$other eq $net && $kind ne "obs"} { continue }
            lassign $br bx0 by0 bx1 by1
            set gap [expr {max($bx0-$ax1,$ax0-$bx1,$by0-$ay1,$ay0-$by1)}]
            if {$minimum eq {} || $gap < $minimum} { set minimum $gap }
        }
    }
    if {$minimum eq {}} { return null }
    return $minimum
}

# Subtract forbidden x intervals, retaining exact boundary-touch-at-clearance.
proc ::hc_pdn::subtract {intervals lo hi} {
    set result {}
    foreach interval $intervals {
        lassign $interval a b
        if {$hi <= $a || $lo >= $b} { lappend result $interval; continue }
        if {$a < $lo} { lappend result [list $a $lo] }
        if {$hi < $b} { lappend result [list $hi $b] }
    }
    return $result
}

# Find one legal pin neck and external horizontal landing, connected by positive
# overlap. Both added rectangles stay in the declared halo except the 0.4um pin
# penetration. No supply bar or intervening opposite-net stripe may be crossed.
# A candidate is {score pin_rect grid_rect neck_rect landing_rect edge}.
proc ::hc_pdn::search {net pins stripes blockers footprint halo bounds edges} {
    variable clearance
    variable neck
    variable overlap
    lassign $footprint mx0 my0 mx1 my1
    set candidates {}
    foreach edge $edges {
        foreach pin $pins {
            lassign $pin px0 py0 px1 py1
            if {$edge eq "bottom" && $py0 != $my0} { continue }
            if {$edge eq "top" && $py1 != $my1} { continue }
            foreach stripe $stripes {
                lassign $stripe sx0 sy0 sx1 sy1
                if {$sx1-$sx0 < $overlap} { continue }
                if {$edge eq "bottom"} {
                    set ly1 [snap_down [expr {min($my0-$clearance,$sy1+$neck-$overlap)}]]
                    set ly0 [expr {$ly1-$neck}]
                    set ny0 $ly0
                    set ny1 [expr {$my0+$overlap}]
                    if {$ly0 < $my0-$halo} { continue }
                } else {
                    set ly0 [snap_up [expr {max($my1+$clearance,$sy0-$neck+$overlap)}]]
                    set ly1 [expr {$ly0+$neck}]
                    set ny0 [expr {$my1-$overlap}]
                    set ny1 $ly1
                    if {$ly1 > $my1+$halo} { continue }
                }
                if {min($ly1,$sy1)-max($ly0,$sy0) < $overlap} { continue }
                # Narrow to pin intervals whose complete vertical neck clears OBS,
                # signals and every opposite supply, including other macros.
                set intervals [list [list $px0 $px1]]
                foreach blocker $blockers {
                    lassign $blocker bn br kind
                    if {$bn eq $net && $kind ne "obs"} { continue }
                    lassign $br bx0 by0 bx1 by1
                    if {$ny1+$clearance <= $by0 || $by1+$clearance <= $ny0} { continue }
                    set intervals [subtract $intervals [expr {$bx0-$clearance}] [expr {$bx1+$clearance}]]
                }
                foreach interval $intervals {
                    lassign $interval a b
                    set a [snap_up $a]
                    set b [snap_down $b]
                    if {$b-$a < $neck} { continue }
                    # The closest feasible neck to this stripe minimizes detours.
                    set nx0 [snap_down [expr {max($a,min($b-$neck,($sx0+$sx1-$neck)/2.0))}]]
                    set nx1 [expr {$nx0+$neck}]
                    set nr [list $nx0 $ny0 $nx1 $ny1]
                    set lr [list [expr {min($nx0,$sx0)}] $ly0 [expr {max($nx1,$sx1)}] $ly1]
                    if {![legal $nr $net $blockers $bounds] || ![legal $lr $net $blockers $bounds]} { continue }
                    if {![inside $lr [expand $footprint $halo]]} { continue }
                    if {![contact $nr $pin $neck $overlap] || ![contact $lr $stripe $overlap $overlap] ||
                        ![contact $lr $nr $neck $overlap]} { continue }
                    set score [expr {[lindex $lr 2]-[lindex $lr 0]}]
                    lappend candidates [list $score $pin $stripe $nr $lr $edge]
                }
            }
        }
    }
    # Sorting on the complete candidate gives stable tie-breaking independent of
    # OpenDB object enumeration. Numeric score is primary; coordinates break ties.
    if {[llength $candidates] == 0} { return {} }
    return [lindex [lsort -command ::hc_pdn::candidate_compare $candidates] 0]
}
proc ::hc_pdn::candidate_compare {a b} {
    if {[lindex $a 0] != [lindex $b 0]} { return [expr {[lindex $a 0] < [lindex $b 0] ? -1 : 1}] }
    return [string compare $a $b]
}
proc ::hc_pdn::json_string {s} {
    set out {"}
    foreach c [split $s {}] {
        scan $c %c n
        switch -- $c {
            "\"" { append out {\"} }
            "\\" { append out {\\} }
            default {
                if {$n < 32} { append out [format {\u%04x} $n] } else { append out $c }
            }
        }
    }
    append out {"}
    return $out
}
proc ::hc_pdn::json_rect {r} { return "\[[join $r ,]\]" }
|tcl}

let runtime = {tcl|
# Begin runtime: OpenDB adapter and native-pdngen hook.
proc ::hc_pdn::um {value} {
    variable dbu
    variable grid
    set v [expr {double($value)*$dbu}]
    set i [expr {round($v)}]
    if {abs($v-$i) > 0.000001 || $i % $grid != 0} { fail "non-grid-aligned micrometre value $value" }
    return $i
}
proc ::hc_pdn::master_rect {box x y} { return [translate [rect $box] $x $y] }
proc ::hc_pdn::layer_is_m4 {box} {
    set layer [$box getTechLayer]
    return [expr {$layer ne "NULL" && [$layer getName] eq "Metal4"}]
}
proc ::hc_pdn::pin_rects {inst pin} {
    set term [[$inst getMaster] findMTerm $pin]
    if {$term eq "NULL"} { fail "[$inst getName] has no $pin master pin" }
    set iterm [$inst findITerm $pin]
    if {$iterm eq "NULL" || [$iterm getNet] eq "NULL"} { fail "unconnected supply [$inst getName]/$pin" }
    set expected [expr {$pin eq "VSS!" ? "VGND" : "VPWR"}]
    if {[[$iterm getNet] getName] ne $expected} { fail "incorrect net on [$inst getName]/$pin" }
    set expected_type [expr {$pin eq "VSS!" ? "GROUND" : "POWER"}]
    if {[$term getSigType] ne $expected_type} { fail "incorrect supply type on $pin" }
    lassign [rect [$inst getBBox]] x y ignored ignored
    set result {}
    foreach mpin [$term getMPins] {
        foreach box [$mpin getGeometry] {
            if {[layer_is_m4 $box]} { lappend result [master_rect $box $x $y] }
        }
    }
    set count [expr {$pin eq "VDDARRAY!" ? 16 : 20}]
    if {[llength $result] != $count} { fail "unexpected exact256x16 Metal4 geometry for $pin" }
    return [lsort -unique $result]
}

# Grid, pin, obstruction and via geometry share one conservative blocker model.
# A via contributes its actual Metal4 enclosure, not the cut's bounding box.
proc ::hc_pdn::grid_geometry {block} {
    set result {}
    foreach net [$block getNets] {
        foreach swire [$net getSWires] {
            foreach box [$swire getWires] {
                if {[$box isVia]} {
                    set via [$box getTechVia]
                    if {$via eq "NULL"} { set via [$box getBlockVia] }
                    if {$via eq "NULL"} { fail "special-wire via has no definition" }
                    lassign [$box getViaXY] x y
                    foreach enclosure [$via getBoxes] {
                        if {[layer_is_m4 $enclosure]} {
                            lappend result [list [$net getName] [master_rect $enclosure $x $y] via]
                        }
                    }
                } elseif {[layer_is_m4 $box]} {
                    lappend result [list [$net getName] [rect $box] stripe]
                }
            }
        }
    }
    return $result
}
proc ::hc_pdn::blockers {block} {
    set result [grid_geometry $block]
    foreach inst [$block getInsts] {
        if {[$inst getOrient] ne "R0" && [[$inst getMaster] isBlock]} {
            fail "unsupported additional non-R0 macro [$inst getName]"
        }
        # Standard-cell Metal4 geometry is absent in the pinned library. Fail on
        # unexpected transformed geometry instead of applying an R0 translation.
        lassign [rect [$inst getBBox]] x y ignored ignored
        foreach obs [[$inst getMaster] getObstructions] {
            if {[layer_is_m4 $obs]} {
                if {[$inst getOrient] ne "R0"} { fail "unsupported oriented Metal4 obstruction on [$inst getName]" }
                lappend result [list {} [master_rect $obs $x $y] obs]
            }
        }
        foreach iterm [$inst getITerms] {
            set net [$iterm getNet]
            set netname [expr {$net eq "NULL" ? "" : [$net getName]}]
            foreach mpin [[$iterm getMTerm] getMPins] {
                foreach box [$mpin getGeometry] {
                    if {[layer_is_m4 $box]} {
                        if {[$inst getOrient] ne "R0"} { fail "unsupported oriented Metal4 pin on [$inst getName]" }
                        lappend result [list $netname [master_rect $box $x $y] pin]
                    }
                }
            }
        }
    }
    foreach obs [$block getObstructions] {
        set box [$obs getBBox]
        if {[layer_is_m4 $box]} { lappend result [list {} [rect $box] obs] }
    }
    foreach term [$block getBTerms] {
        if {[$term getSigType] in {POWER GROUND}} { continue }
        foreach bpin [$term getBPins] {
            foreach box [$bpin getBoxes] {
                if {[layer_is_m4 $box]} { lappend result [list {} [rect $box] signal] }
            }
        }
    }
    return $result
}
proc ::hc_pdn::add_rect {block netname r} {
    variable m4
    set net [$block findNet $netname]
    if {$net eq "NULL"} { fail "missing power net $netname" }
    set wire [odb::dbSWire_create $net ROUTED]
    if {$wire eq "NULL"} { fail "failed to create special wire for $netname" }
    set box [odb::dbSBox_create $wire $m4 {*}$r STRIPE]
    if {$box eq "NULL" || [rect $box] ne $r || ![layer_is_m4 $box]} {
        fail "OpenDB did not create the requested Metal4 bridge for $netname"
    }
}
proc ::hc_pdn::check_instance {block entry} {
    variable dbu
    variable clearance
    lassign $entry resource name master x_um y_um halo_um
    set inst [$block findInst $name]
    if {$inst eq "NULL"} { fail "resource $resource missing actual instance $name" }
    if {[[$inst getMaster] getName] ne $master || [$inst getOrient] ne "R0" || ![$inst isFixed]} {
        fail "resource $resource requires its exact fixed R0 master"
    }
    set bbox [rect [$inst getBBox]]
    lassign $bbox x0 y0 x1 y1
    if {$x0 != [um $x_um] || $y0 != [um $y_um] ||
        $x1-$x0 != [um 236.8] || $y1-$y0 != [um 118.78]} {
        fail "resource $resource actual placement/size differs from plan"
    }
    set halo [um $halo_um]
    if {![inside [expand $bbox $halo] [rect [$block getCoreArea]]]} {
        fail "resource $resource footprint/halo exceeds usable core"
    }
    foreach pin {VDD! VDDARRAY! VSS!} {
        foreach r [pin_rects $inst $pin] {
            if {![inside $r $bbox] || [lindex $r 2]-[lindex $r 0] != [um 2.81]} {
                fail "resource $resource has unexpected local supply geometry"
            }
        }
    }
    foreach iterm [$inst getITerms] {
        set term [$iterm getMTerm]
        if {[$term getSigType] in {POWER GROUND}} { continue }
        foreach mpin [$term getMPins] {
            foreach box [$mpin getGeometry] {
                if {[layer_is_m4 $box]} { fail "resource $resource has unsupported Metal4 signal access" }
            }
        }
    }
    return $inst
}
proc ::hc_pdn::public_pin {block netname all_blockers} {
    variable clearance
    variable neck
    variable m4
    set core [rect [$block getCoreArea]]
    lassign $core cx0 cy0 cx1 cy1
    set choices {}
    foreach b [grid_geometry $block] {
        lassign $b net r kind
        if {$net ne $netname || $kind ne "stripe"} { continue }
        lassign $r x0 y0 x1 y1
        if {$y0 > $cy0 || $y1 < $cy1 || $x1-$x0 < $neck} { continue }
        if {[legal $r $netname $all_blockers [rect [$block getDieArea]]]} { lappend choices $r }
    }
    if {[llength $choices] == 0} { fail "no legal uninterrupted public Metal4 stripe for $netname" }
    set r [lindex [lsort $choices] 0]
    set term [$block findBTerm $netname]
    if {$term eq "NULL"} { fail "missing public supply terminal $netname" }
    if {[$term getNet] eq "NULL" || [[$term getNet] getName] ne $netname} { fail "public terminal $netname has incorrect net" }
    foreach pin [$term getBPins] { odb::dbBPin_destroy $pin }
    set pin [odb::dbBPin_create $term]
    $pin setPlacementStatus FIRM
    set box [odb::dbBox_create $pin $m4 {*}$r]
    if {$box eq "NULL" || [rect $box] ne $r || ![layer_is_m4 $box]} {
        fail "OpenDB did not create the requested public Metal4 pin for $netname"
    }
    return "{\"net\":[json_string $netname],\"layer\":\"Metal4\",\"rect_dbu\":[json_rect $r]}"
}
proc ::hc_pdn::construct {} {
    variable instances
    variable dbu
    variable clearance
    variable neck
    variable overlap
    variable grid
    variable m4
    set block [ord::get_db_block]
    set tech [ord::get_db_tech]
    set dbu [$tech getDbUnitsPerMicron]
    set grid [$tech getManufacturingGrid]
    if {$dbu <= 0 || $grid <= 0} { fail "missing DBU/manufacturing grid" }
    set m4 [$tech findLayer Metal4]
    if {$m4 eq "NULL"} { fail "missing Metal4" }
    set clearance [um 0.6]
    set neck [um 1.4]
    set overlap [um 0.4]
    if {$neck < [$m4 getMinWidth] || $clearance < [$m4 getSpacing]} { fail "technology exceeds supported width/spacing policy" }
    # Validate all placements before modifying any geometry, including halo pairs.
    set footprints {}
    set expected_names {}
    foreach entry $instances { lappend expected_names [lindex $entry 1] }
    foreach inst [$block getInsts] {
        if {[[$inst getMaster] isBlock] && [$inst getName] ni $expected_names} {
            fail "unregistered physical macro [$inst getName]"
        }
    }
    foreach entry $instances {
        set inst [check_instance $block $entry]
        set halo [um [lindex $entry 5]]
        set expanded [expand [rect [$inst getBBox]] $halo]
        foreach prior $footprints { if {![clear $prior $expanded 0]} { fail "actual macro halos overlap" } }
        lappend footprints $expanded
    }
    set all_blockers [blockers $block]
    set reports {}
    foreach entry $instances {
        lassign $entry resource name master x_um y_um halo_um
        set inst [$block findInst $name]
        set footprint [rect [$inst getBBox]]
        set halo [um $halo_um]
        set contacts {}
        foreach supply {VDD! VDDARRAY! VSS!} {
            set net [expr {$supply eq "VSS!" ? "VGND" : "VPWR"}]
            set stripes {}
            foreach b $all_blockers {
                lassign $b bn br kind
                if {$bn eq $net && $kind eq "stripe"} { lappend stripes $br }
            }
            set edges [expr {$supply eq "VDD!" ? "bottom" : ($supply eq "VDDARRAY!" ? "top" : "bottom top")}]
            set candidate [search $net [pin_rects $inst $supply] $stripes $all_blockers $footprint $halo [rect [$block getCoreArea]] $edges]
            if {$candidate eq {}} { fail "resource $resource ($name) has no legal edge contact for $supply; change explicit placement/halo" }
            lassign $candidate score pin stripe nr lr edge
            set measured [measured_clearance [list $nr $lr] $net $all_blockers]
            add_rect $block $net $nr
            add_rect $block $net $lr
            lappend all_blockers [list $net $nr bridge] [list $net $lr bridge]
            lappend contacts "{\"pin\":[json_string $supply],\"net\":[json_string $net],\"edge\":[json_string $edge],\"pin_rect_dbu\":[json_rect $pin],\"grid_rect_dbu\":[json_rect $stripe],\"neck_rect_dbu\":[json_rect $nr],\"landing_rect_dbu\":[json_rect $lr],\"minimum_clearance_dbu\":$clearance,\"measured_minimum_clearance_dbu\":$measured,\"minimum_contact_width_dbu\":$neck,\"minimum_overlap_dbu\":$overlap}"
        }
        lappend reports "{\"resource\":[json_string $resource],\"instance\":[json_string $name],\"module\":[json_string $master],\"orientation\":\"R0\",\"footprint_dbu\":[json_rect $footprint],\"halo_dbu\":$halo,\"contacts\":\[[join $contacts ,]\]}"
    }
    # Include added opposite-net bridges when selecting the public supply pins.
    set public {}
    foreach net {VPWR VGND} { lappend public [public_pin $block $net $all_blockers] }
    set output [file join $::env(STEP_DIR) macro-power-geometry.json]
    set channel [open $output {WRONLY CREAT EXCL}]
    try {
        puts $channel "{\"schema_version\":1,\"strategy\":\"cmos5l_m4_edge_access_v1\",\"dbu_per_um\":$dbu,\"manufacturing_grid_dbu\":$grid,\"macros\":\[[join $reports ,]\],\"public_pins\":\[[join $public ,]\]}"
    } finally { close $channel }
}

source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_global_connections.tcl
set_global_connections
set_voltage_domain -name CORE -power $::env(VDD_NET) -ground $::env(GND_NET)
define_pdn_grid -name stdcell_grid -starts_with POWER -voltage_domains CORE -pins Metal4
add_pdn_stripe -grid stdcell_grid -layer Metal4 -width $::env(PDN_VWIDTH) \
    -pitch $::env(PDN_VPITCH) -offset $::env(PDN_VOFFSET) \
    -spacing $::env(PDN_VSPACING) -starts_with POWER
add_pdn_stripe -grid stdcell_grid -layer $::env(PDN_RAIL_LAYER) -width $::env(PDN_RAIL_WIDTH) -followpins
add_pdn_connect -grid stdcell_grid -layers [list $::env(PDN_RAIL_LAYER) Metal4]
# Do not define an empty native macro grid: on this same-Metal4 target it has
# no stripes/vias and pdngen rejects the full grid (PDN-0233). Native stdcell
# generation still respects imported macro geometry; explicit checked edge access
# supplies the macro afterward. Global supply connections above remain enabled.

if {[llength [info commands ::hc_pdn::native_pdngen]] != 0} { ::hc_pdn::fail "PDN wrapper already installed" }
rename ::pdngen ::hc_pdn::native_pdngen
proc ::pdngen {args} {
    try {
        ::hc_pdn::native_pdngen {*}$args
        ::hc_pdn::construct
    } finally {
        rename ::pdngen {}
        rename ::hc_pdn::native_pdngen ::pdngen
    }
}
|tcl}
