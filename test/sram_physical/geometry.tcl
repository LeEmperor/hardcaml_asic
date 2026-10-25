# These tests source the actual emitted geometry implementation, without OpenROAD.
proc assert {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
set ::hc_pdn::grid 5
set ::hc_pdn::clearance 600
set ::hc_pdn::neck 1400
set ::hc_pdn::overlap 400

set footprint {10000 10000 30000 20000}
set bounds {0 0 60000 60000}
set pins {{14000 10000 16810 15000}}
set stripes {{14500 0 16600 8520}}
set blockers {{{} {12000 10000 13740 20000} obs} {VGND {18600 0 20700 30000} stripe}}
set c [::hc_pdn::search VPWR $pins $stripes $blockers $footprint 2000 $bounds bottom]
assert {$c ne {}} "valid edge connection not found"
lassign $c score pin stripe nr lr edge
assert {[::hc_pdn::contact $nr $pin 1400 400]} "pin contact is inadequate"
assert {[::hc_pdn::contact $lr $stripe 400 400]} "grid contact is inadequate"
assert {[::hc_pdn::legal $nr VPWR $blockers $bounds]} "neck touches obstruction/opposite net"
assert {[lindex $lr 1] >= 8000 && [lindex $nr 3] == 10400} "bridge exceeds policy corridor"

# Translation equivariance proves placement is an input, not a probe coordinate.
set shifted_pins {}
foreach r $pins { lappend shifted_pins [::hc_pdn::translate $r 1000 5000] }
set shifted_stripes {}
foreach r $stripes { lappend shifted_stripes [::hc_pdn::translate $r 1000 5000] }
set shifted_blockers {}
foreach b $blockers { lassign $b n r k; lappend shifted_blockers [list $n [::hc_pdn::translate $r 1000 5000] $k] }
set moved [::hc_pdn::search VPWR $shifted_pins $shifted_stripes $shifted_blockers [::hc_pdn::translate $footprint 1000 5000] 2000 $bounds bottom]
assert {[lindex $moved 3] eq [::hc_pdn::translate $nr 1000 5000]} "placement translation changed neck policy"
assert {[lindex $moved 4] eq [::hc_pdn::translate $lr 1000 5000]} "placement translation changed landing policy"

# A same-layer opposite-net stripe between pin and grid forbids the detour.
set rejected [::hc_pdn::search VPWR {{18000 10000 20810 15000}} {{10000 0 12100 9000}} \
    {{VGND {14000 0 16100 30000} stripe}} $footprint 2000 $bounds bottom]
assert {$rejected eq {}} "bridge crossed opposite supply"
set rejected [::hc_pdn::search VPWR $pins $stripes \
    {{{} {13700 9900 17000 11000} obs}} $footprint 2000 $bounds bottom]
assert {$rejected eq {}} "bridge crossed pin-edge obstruction"
set rejected [::hc_pdn::search VPWR {{14000 10000 15000 15000}} $stripes {} $footprint 2000 $bounds bottom]
assert {$rejected eq {}} "accepted subminimum contact width"
set rejected [::hc_pdn::search VPWR $pins {{14500 0 16600 6000}} {} $footprint 2000 $bounds bottom]
assert {$rejected eq {}} "bridge silently exceeded halo"
set rejected [::hc_pdn::search VPWR $pins $stripes $blockers $footprint 2000 {20000 0 60000 60000} bottom]
assert {$rejected eq {}} "bridge escaped core"
assert {![::hc_pdn::contact {0 0 1400 400} {0 400 1400 1000} 1 1]} "zero-area abutment counted as contact"
assert {[::hc_pdn::clear {0 0 1000 1000} {1600 0 2000 1000} 600]} "exact legal clearance rejected"
assert {![::hc_pdn::clear {0 0 1000 1000} {1595 0 2000 1000} 600]} "off-by-one clearance accepted"

# Top access reaches VDDARRAY independently without crossing its internal bar.
set top [::hc_pdn::search VPWR {{14000 16000 16810 20000}} {{14500 21480 16600 40000}} \
    {{{} {13000 15000 18000 15500} obs}} $footprint 2000 $bounds top]
assert {$top ne {} && [lindex $top 5] eq "top"} "upper-array edge access missing"
assert {[lindex [lindex $top 3] 1] == 19600} "upper contact penetrated too far"

# Irregular support bands: search all pin rectangles, not a fixed column index.
set irregular [::hc_pdn::search VPWR {{14000 10000 16810 15000} {24000 10000 26810 15000}} \
    {{24500 0 26600 8520}} {{{} {13000 9900 18000 11000} obs}} $footprint 2000 $bounds bottom]
assert {$irregular ne {} && [lindex [lindex $irregular 1] 0] == 24000} "irregular-column search failed"
puts "geometry: 18 contact/clearance/translation/obstruction assertions passed"
