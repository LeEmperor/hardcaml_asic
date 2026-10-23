"""Versioned, bounded coarse plans, independent of CLI and runtime bindings.

These are sequential service actions, not LibreLane step hooks or checkpoints.
Preflight and input staging remain owned by the coarse implementation action.
Action keys are semantic identities; labels are presentation only. A recipe's
plan is reusable across attempts and contains neither run IDs nor image bindings.
"""

from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class Action:
    key: str
    operation: str
    stage: str
    label: str
    enabled: bool = True
    requires: tuple[str, ...] = ()
    gate: str = "success"
    inputs: tuple[str, ...] = ()
    outputs: tuple[str, ...] = ()

    def as_dict(self):
        value = asdict(self)
        for name in ("requires", "inputs", "outputs"):
            value[name] = list(value[name])
        return value


@dataclass(frozen=True)
class Plan:
    endpoint: str
    actions: tuple[Action, ...]
    schema_version: int = 1

    def __post_init__(self):
        if type(self.schema_version) is not int or self.schema_version != 1 or self.endpoint not in ("synthesis", "full"):
            raise ValueError("unsupported coarse execution plan")
        if not isinstance(self.actions, tuple) or len(self.actions) != 5 or not all(
                isinstance(action, Action) for action in self.actions):
            raise ValueError("expected the five coarse service actions")
        expected = coarse_actions(self.endpoint, self.actions[-1].enabled)
        # Composition is deliberately bounded in slice 1. Only display labels
        # may vary; executable contracts cannot be silently edited by a reader.
        if len(self.actions) != len(expected):
            raise ValueError("expected the five coarse service actions")
        for actual, contract in zip(self.actions, expected):
            if not isinstance(actual, Action) or not isinstance(actual.label, str):
                raise ValueError("malformed coarse action")
            if any(not isinstance(getattr(actual, name), tuple) or not all(
                    isinstance(item, str) for item in getattr(actual, name))
                   for name in ("requires", "inputs", "outputs")):
                raise ValueError("action contracts must use immutable string tuples")
            value, wanted = actual.as_dict(), contract.as_dict()
            value.pop("label")
            wanted.pop("label")
            if value != wanted or type(actual.enabled) is not bool:
                raise ValueError(f"unsupported coarse action contract: {actual.key}")

    def as_dict(self):
        return {"schema_version": self.schema_version, "endpoint": self.endpoint,
                "actions": [action.as_dict() for action in self.actions]}

    @classmethod
    def from_dict(cls, value):
        if not isinstance(value, dict) or set(value) != {"schema_version", "endpoint", "actions"}:
            raise ValueError("malformed execution plan fields")
        if not isinstance(value["actions"], list) or len(value["actions"]) != 5:
            raise ValueError("expected the five coarse service actions")
        actions = []
        for raw in value["actions"]:
            if not isinstance(raw, dict) or set(raw) != set(Action.__dataclass_fields__):
                raise ValueError("malformed coarse action fields")
            fields = dict(raw)
            for name in ("requires", "inputs", "outputs"):
                if not isinstance(fields[name], list):
                    raise ValueError(f"expected action {name} list")
                fields[name] = tuple(fields[name])
            actions.append(Action(**fields))
        return cls(value["endpoint"], tuple(actions), value["schema_version"])


def coarse_actions(endpoint, archive):
    return (
        Action("implementation.librelane", "run", "implementation", "LibreLane",
               inputs=("bundle", "runtime_requirements"),
               outputs=("run_record", "implementation_workdir")),
        Action("verification.postcheck", "postcheck", "verification", "Postcheck",
               enabled=endpoint == "full", requires=("implementation.librelane",),
               inputs=("implementation_workdir", "testbench"), outputs=("check_record",)),
        Action("results.collect", "collect", "results", "Collect",
               requires=(("implementation.librelane", "verification.postcheck")
                         if endpoint == "full" else ("implementation.librelane",)),
               gate="run_available",
               inputs=("run_record", "implementation_workdir"), outputs=("results",)),
        Action("acceptance.report", "report", "acceptance", "Acceptance",
               requires=("results.collect",), inputs=("results",), outputs=("verdict",)),
        Action("retention.archive", "archive", "retention", "Archive", enabled=archive,
               requires=("acceptance.report",), gate="accepted",
               inputs=("run_record", "results"), outputs=("archive",)),
    )


def resolve(endpoint, *, archive=False):
    """Resolve the supported recipe without probing tools or allocating results."""
    return Plan(endpoint, coarse_actions(endpoint, archive))


# Tested with official Classic in this exact image; not a general backend promise.
TESTED_IMAGE = "sha256:d109140b8f17fc54f4fca998beb8124f4949404ec52e339eebd2250854a18b5a"
BOUNDARIES = {"synthesis": "Yosys.Synthesis", "floorplan": "OpenROAD.Floorplan",
              "placement": "OpenROAD.DetailedPlacement", "cts": "OpenROAD.CTS",
              "routing": "OpenROAD.DetailedRouting", "timing": "OpenROAD.STAPostPNR", "signoff": "Misc.ReportManufacturability"}
STAGE_ORDER = tuple(BOUNDARIES)
LEGACY_STAGE_ORDER = tuple(s for s in STAGE_ORDER if s != "timing")
SUCCESSORS = {"synthesis": "Checker.YosysUnmappedCells", "floorplan": "OpenROAD.DumpRCValues",
              "placement": "OpenROAD.CTS", "cts": "OpenROAD.STAMidPNR-1",
              "routing": "Odb.RemoveRoutingObstructions", "timing": "OpenROAD.IRDropReport"}
# The direct synthesis -> placement segment is retained as a proven standalone
# API. Recipes expand the contiguous sequence and never elide a physical stage.
RESTART_TARGETS = {"synthesis": ("floorplan", "placement"), "floorplan": ("placement",),
                   "placement": ("cts",), "cts": ("routing",), "routing": ("timing",), "timing": ("signoff",),
                   "signoff": ()}


def boundary_capabilities():
    return {name: {"endpoint": endpoint, "restart_supported": bool(RESTART_TARGETS[name]),
                   "restart_targets": list(RESTART_TARGETS[name]),
                   "successor": SUCCESSORS.get(name), "tested_image_id": TESTED_IMAGE,
                   "closure_scope": "path_bound",
                   "acceptance": "not_evaluated"} for name, endpoint in BOUNDARIES.items()}


@dataclass(frozen=True)
class StagePlan:
    endpoint: str
    resume: bool = False
    schema_version: int = 4
    stages: tuple[str, ...] = ()
    initial_boundary: str | None = None

    def __post_init__(self):
        if self.schema_version == 4 and not self.stages and self.endpoint in STAGE_ORDER:
            source = self.initial_boundary or ("synthesis" if self.resume else None)
            start = STAGE_ORDER.index(source) + 1 if source in STAGE_ORDER else 0
            object.__setattr__(self, "initial_boundary", source)
            object.__setattr__(self, "stages", STAGE_ORDER[start:STAGE_ORDER.index(self.endpoint) + 1])
        if (type(self.schema_version) is not int or self.schema_version not in (2, 3, 4)
                or not isinstance(self.endpoint, str) or self.endpoint not in BOUNDARIES
                or type(self.resume) is not bool
                or (self.resume and self.endpoint == "synthesis")):
            raise ValueError("unsupported stage recipe")
        if self.schema_version == 2:
            if self.stages or self.initial_boundary is not None or self.endpoint == "timing":
                raise ValueError("legacy endpoint recipe cannot contain sequence fields")
        else:
            if (not isinstance(self.stages, tuple) or not self.stages
                    or not all(isinstance(s, str) and s in BOUNDARIES for s in self.stages)
                    or self.stages[-1] != self.endpoint
                    or self.resume != (self.initial_boundary is not None)):
                raise ValueError("malformed explicit stage sequence")
            start = 0
            if self.initial_boundary is not None:
                if (not isinstance(self.initial_boundary, str) or self.initial_boundary not in SUCCESSORS
                        or self.initial_boundary not in self.order):
                    raise ValueError("unsupported initial boundary")
                start = self.order.index(self.initial_boundary) + 1
            if self.stages != self.order[start:start + len(self.stages)]:
                raise ValueError("stage sequence must be contiguous; required Classic stages cannot be skipped")

    @property
    def order(self):
        return STAGE_ORDER if self.schema_version == 4 else LEGACY_STAGE_ORDER

    @property
    def source_boundary(self):
        return ("synthesis" if self.resume else None) if self.schema_version == 2 else self.initial_boundary

    @property
    def sequence(self):
        return (self.order[1 if self.resume else 0:self.order.index(self.endpoint) + 1]
                if self.schema_version == 2 else self.stages)

    @property
    def actions(self):
        names = self.sequence
        return tuple(Action("implementation." + name, "segment", name, name,
                            requires=(() if i == 0 else ("implementation." + names[i - 1],)),
                            inputs=(((names[i - 1] if i else self.source_boundary) + "_checkpoint",)
                                    if name != "synthesis" else ("bundle",)),
                            outputs=(name + "_checkpoint",))
                     for i, name in enumerate(names))

    def as_dict(self):
        if self.schema_version in (3, 4):
            return {"schema_version": self.schema_version, "stages": list(self.stages), "initial_boundary": self.initial_boundary}
        return {"schema_version": 2, "endpoint": self.endpoint, "resume": self.resume}

    @classmethod
    def from_dict(cls, value):
        if isinstance(value, dict) and value.get("schema_version") in (3, 4):
            if (type(value["schema_version"]) is not int
                    or set(value) != {"schema_version", "stages", "initial_boundary"}
                    or not isinstance(value["stages"], list) or not value["stages"]):
                raise ValueError("malformed explicit stage recipe")
            return cls(value["stages"][-1], value["initial_boundary"] is not None, value["schema_version"],
                       tuple(value["stages"]), value["initial_boundary"])
        if not isinstance(value, dict) or set(value) != {"schema_version", "endpoint", "resume"}:
            raise ValueError("malformed stage recipe")
        return cls(**value)


def resolve_stages(endpoint, *, resume=False, initial_boundary=None):
    """Bounded standalone/composed stages, without runtime or store defaults."""
    if initial_boundary is not None:
        if endpoint not in BOUNDARIES or initial_boundary not in SUCCESSORS:
            raise ValueError("unsupported stage boundary")
        return resolve_sequence(STAGE_ORDER[STAGE_ORDER.index(initial_boundary) + 1:
                                           STAGE_ORDER.index(endpoint) + 1],
                                initial_boundary=initial_boundary)
    return resolve_sequence(STAGE_ORDER[1 if resume else 0:STAGE_ORDER.index(endpoint) + 1],
                            initial_boundary="synthesis" if resume else None)


def resolve_sequence(stages, *, initial_boundary=None):
    """Validate explicit contiguous composition before allocating a runtime."""
    names = tuple(stages)
    if not names:
        raise ValueError("empty stage sequence")
    return StagePlan(names[-1], initial_boundary is not None, 4, names, initial_boundary)
