"""Strict Tcl OpenDB adapter fixture; no OpenROAD import or executable.

Uses the exact stock pin columns (including irregular central support columns).
Grid rectangles are synthetic native-output inputs, never production geometry.
Unknown adapter methods fail rather than returning permissive defaults.
"""


def fixture(output, variant="ok"):
    declarations = []
    counter = 0

    def obj(**methods):
        nonlocal counter
        counter += 1
        name = f"::fixture::o{counter}"
        entries = " ".join("{" + k + "} {" + str(v) + "}" for k, v in methods.items())
        declarations.append(f"set ::fixture::methods({name}) [dict create {entries}]\ninterp alias {{}} {name} {{}} ::fixture::dispatch {name}\n")
        return name

    layer = obj(getName="Metal4", getMinWidth=200, getSpacing=210)

    def rect(r):
        return obj(xMin=r[0], yMin=r[1], xMax=r[2], yMax=r[3], getTechLayer=layer, isVia=0)

    def wire(r):
        return obj(getWires=rect(r))

    # Supply columns from exact stock LEF, in integer nanometres. The native
    # fixture's grid only covers one safe local array pair at both macro edges.
    array_x = [4260, 15500, 26740, 37980, 49220, 60460, 71700, 82940,
               151050, 162290, 173530, 184770, 196010, 207250, 218490, 229730]
    ground_x = [9880, 21120, 32360, 43600, 54840, 66080, 77320, 88560,
                98970, 109270, 124720, 135020, 145430, 156670, 167910,
                179150, 190390, 201630, 212870, 224110]
    powers = [(x, 0, x + 2810, 38825) for x in array_x]
    powers += [(x, 0, x + 2810, 118780) for x in [104120, 114420, 119570, 129870]]
    arrays = [(x, 45465, x + 2810, 118780) for x in array_x]
    grounds = [(x, 0, x + 2810, 118780) for x in ground_x]
    # Real local OBS near the selected column, plus a split-supply obstruction.
    obs = [rect(r) for r in [(69150, 0, 71440, 118780), (74770, 0, 77060, 118780),
                            (80390, 0, 82680, 118780), (69150, 39085, 77060, 45205)]]
    net_names = {n: obj(getName=n) for n in ["VPWR", "VGND"]}
    insts = []
    for name, x in [("left", 40000), ("right", 400000)]:
        terms, iterms = {}, []
        for pin, boxes in [("VDD!", powers), ("VDDARRAY!", arrays), ("VSS!", grounds)]:
            term = obj(getSigType="GROUND" if pin == "VSS!" else "POWER",
                       getMPins=" ".join(obj(getGeometry=rect(r)) for r in boxes))
            terms[f"findMTerm:{pin}"] = term
            net = net_names["VGND" if pin == "VSS!" else "VPWR"]
            if variant == "wrong_net" and name == "left" and pin == "VDDARRAY!":
                net = net_names["VGND"]
            iterm = obj(getNet=net, getMTerm=term)
            terms[f"findITerm:{pin}"] = iterm
            iterms.append(iterm)
        master = obj(getName="RM_IHPSG13_1P_256x16_c2_bm_bist", isBlock=1,
                     getObstructions=" ".join(obs),
                     **{k: v for k, v in terms.items() if k.startswith("findMTerm:")})
        inst = obj(getMaster=master, getOrient="MX" if variant == "orientation" else "R0",
                   isFixed=1, getName=f"hc_resource_{len(name)}_{name}",
                   getBBox=rect([x, 81000, x + 236800 + (5 if variant == "size" else 0), 199780]),
                   getITerms=" ".join(iterms),
                   **{k: v for k, v in terms.items() if k.startswith("findITerm:")})
        insts.append((name, inst))
    nets = []
    for n in ["VPWR", "VGND"]:
        swires = []
        if variant != "no_grid":
            for x in [40000, 400000]:
                left = x + (71830 if n == "VPWR" else 75930)
                swires += [wire([left, 3560, left + 2100, 79520]),
                           wire([left, 201310, left + 2100, 707080])]
            public_x = 800000 if n == "VPWR" else 810000
            swires.append(wire([public_x, 3560, public_x + 2100, 707080]))
        if n == "VGND":
            enclosure = [-250000, -3000, 250000, 121000] if variant == "via_collision" else [-100, -100, 100, 100]
            via = obj(getBoxes=rect(enclosure))
            box = obj(isVia=1, getTechVia=via, getViaXY="200000 80000" if variant == "via_collision" else "950000 65000")
            swires.append(obj(getWires=box))
        # Populate the already referenced net's strict methods.
        declarations.append(f"dict set ::fixture::methods({net_names[n]}) getSWires {{{' '.join(swires)}}}\n")
        nets.append(net_names[n])
    public_terms = {n: obj(getSigType="POWER" if n == "VPWR" else "GROUND", getBPins="", getNet=net_names[n]) for n in ["VPWR", "VGND"]}
    # A true dbObstruction exposes geometry through getBBox, not getTechLayer.
    block_obs = obj(getBBox=rect([900000, 50000, 910000, 60000]))
    block = obj(getInsts=" ".join(i for _, i in insts), getNets=" ".join(nets),
                getBTerms=" ".join(public_terms.values()), getObstructions=block_obs,
                getCoreArea=rect([2880, 3780, 1286400, 706860]),
                getDieArea=rect([0, 0, 1289280, 710640]),
                **{f"findInst:hc_resource_{len(n)}_{n}": i for n, i in insts},
                **{f"findNet:{n}": i for n, i in net_names.items()},
                **{f"findBTerm:{n}": i for n, i in public_terms.items()})
    tech = obj(getDbUnitsPerMicron=1000, getManufacturingGrid=5, **{"findLayer:Metal4": layer})
    prefix = r'''
namespace eval ::fixture { variable methods; variable additions {}; variable native_called 0; variable sequence 0; variable empty_macro_grid 0 }
proc ::fixture::dispatch {name method args} {
    if {[llength $args] != 0} { append method :[join $args :] }
    if {![dict exists $::fixture::methods($name) $method]} { error "unknown OpenDB fixture method $name $method" }
    return [dict get $::fixture::methods($name) $method]
}
namespace eval ::ord {}
namespace eval ::odb {}
proc ::fixture::new_rect {layer x0 y0 x1 y1} {
    set name ::fixture::added[incr ::fixture::sequence]
    set ::fixture::methods($name) [dict create xMin $x0 yMin $y0 xMax $x1 yMax $y1 getTechLayer $layer]
    interp alias {} $name {} ::fixture::dispatch $name
    return $name
}
proc source {path} {
    if {$path ni {/fixture/openroad/common/io.tcl /fixture/openroad/common/set_global_connections.tcl}} { error "unexpected source $path" }
}
proc set_global_connections {} {}
proc set_voltage_domain {args} {}
proc define_pdn_grid {args} {
    if {"-macro" in $args} { set ::fixture::empty_macro_grid 1 }
}
proc add_pdn_stripe {args} {}
proc add_pdn_connect {args} {}
proc pdngen {args} {
    set ::fixture::native_called 1
    if {$args ne {-skip_trim}} {error "lost native args"}
    if {$::fixture::empty_macro_grid} {error {PDN-0233: empty same-Metal4 macro grid}}
}
proc ::odb::dbSWire_create {net status} { return $net }
proc ::odb::dbSBox_create {wire layer x0 y0 x1 y1 type} {
    if {!$::fixture::native_called} { error "bridge inserted before native grid" }
    lappend ::fixture::additions [list $wire $x0 $y0 $x1 $y1]
    return [::fixture::new_rect $layer $x0 $y0 $x1 $y1]
}
proc ::odb::dbBPin_destroy {pin} {}
proc ::odb::dbBPin_create {term} { return ::fixture::bpin }
proc ::fixture::bpin {method value} {
    if {$method ne "setPlacementStatus" || $value ne "FIRM"} { error "invalid BPin status" }
}
proc ::odb::dbBox_create {pin layer x0 y0 x1 y1} { return [::fixture::new_rect $layer $x0 $y0 $x1 $y1] }
set ::env(SCRIPTS_DIR) /fixture
set ::env(VDD_NET) VPWR
set ::env(GND_NET) VGND
foreach {k v} {PDN_VWIDTH 2.1 PDN_VPITCH 50 PDN_VOFFSET 10 PDN_VSPACING 2 PDN_RAIL_LAYER Metal1 PDN_RAIL_WIDTH 0.44} { set ::env($k) $v }
'''
    if variant == "native_error":
        prefix += "proc pdngen {args} {error {synthetic native failure}}\n"
    prefix += f"set ::env(STEP_DIR) {{{output}}}\n"
    prefix += "".join(declarations)
    prefix += f"proc ::ord::get_db_block {{}} {{return {block}}}\nproc ::ord::get_db_tech {{}} {{return {tech}}}\n"
    return prefix
