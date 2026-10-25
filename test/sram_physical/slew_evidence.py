"""Checks for the bounded native-buffering experiment; not a signoff substitute."""
import re


def cells(text):
    result = {}
    for kind, name, body in re.findall(r"^\s*((?:sg13cmos5l_|RM_IHPSG13_)\w+)\s+(\S+)\s*\((.*?)\);", text, re.M | re.S):
        ports = dict(re.findall(r"\.\s*(\\[^\s]+|[A-Za-z_]\w*)\s*\(([^()]*)\)", body))
        if name in result:
            raise ValueError("duplicate instance")
        result[name] = kind, ports
    if not result:
        raise ValueError("empty cell inventory")
    return result


def verify_buffer_only(original, candidate):
    """Contract added A->X buffers and compare every original cell connection.

    Rejects new registers/inverters, missing/resized original cells, changed
    controls/data, buffer loops and unsupported buffer interfaces. This deliberately
    proves the observed buffer-only candidate rather than general Verilog EQY.
    """
    before, after = cells(original), cells(candidate)
    if not before.keys() <= after.keys():
        raise ValueError("original instance removed")
    added = after.keys() - before.keys()
    aliases = {}
    clean = lambda s: re.sub(r"\s+", "", s).lstrip("\\")
    for name in added:
        kind, ports = after[name]
        if not re.fullmatch(r"sg13cmos5l_buf_(1|2|4|8|16)", kind) or set(ports) != {"A", "X"}:
            raise ValueError("new cell is not a supported non-inverting combinational buffer")
        output, source = clean(ports["X"]), clean(ports["A"])
        if output in aliases:
            raise ValueError("duplicate new buffer driver")
        aliases[output] = source

    def resolve(name):
        name = name.lstrip("\\")
        seen = set()
        while name in aliases:
            if name in seen:
                raise ValueError("buffer loop")
            seen.add(name)
            name = aliases[name]
        return name

    def expression(value):
        value = re.sub(r"\\[^\s,{}]+|[A-Za-z_][A-Za-z0-9_$]*(?:\[[0-9]+\])?",
                       lambda m: resolve(m.group()), value)
        return re.sub(r"\s+", "", value)

    for name, (kind, ports) in before.items():
        new_kind, new_ports = after[name]
        if kind != new_kind or set(ports) != set(new_ports):
            raise ValueError("original cell type/interface changed: " + name)
        if any(expression(value) != expression(new_ports[port]) for port, value in ports.items()):
            raise ValueError("buffer contraction changed original connectivity: " + name)
    return len(added)


def path_values(text, pin):
    values = []
    for line in text.splitlines():
        match = re.match(r"(.*?)\s([\^v])\s" + re.escape(pin) + r"(?:\s|$)", line)
        if not match:
            continue
        fields = match[1].split()
        if len(fields) < 3:
            continue
        numbers = list(map(float, fields))
        values.append({"edge": "rise" if match[2] == "^" else "fall", "slew_ns": numbers[-3],
                       "load_pf": numbers[-4] if len(numbers) >= 5 else None})
    if not values:
        raise ValueError("no timed path through " + pin)
    return values
