"""Independently callable segments and shared-runner adapter.

SegmentAdapter takes an explicit execution transport and publication store. The
separate prepare service binds runtime once and stages inputs for the CLI. Neither
segment implementation chooses a transport/store or performs hidden sequencing.
"""

import copy
from dataclasses import dataclass
import json
from pathlib import Path
import shutil
import uuid

from . import checkpoint as checkpoints, execution_transport as transport, phase4, result_store
from .execution_plan import StagePlan, BOUNDARIES, TESTED_IMAGE


@dataclass(frozen=True)
class SegmentResult:
    boundary: str
    candidate: Path
    status: str
    exit_code: int

    def as_dict(self):
        return {"boundary": self.boundary, "candidate": str(self.candidate),
                "status": self.status, "exit_code": self.exit_code}


class SegmentAdapter:
    def __init__(self, *, project, pdk_root, compatibility, launch, checkpoint_store,
                 initial_checkpoint=None):
        self.project, self.pdk_root = Path(project), Path(pdk_root)
        self.compatibility = copy.deepcopy(compatibility)
        self.launch = launch
        self.checkpoint_store = Path(checkpoint_store)
        self.initial_checkpoint = initial_checkpoint
        self.current_checkpoint = initial_checkpoint

    def validate(self, plan):
        if not isinstance(plan, StagePlan) or plan.resume != (self.initial_checkpoint is not None):
            raise ValueError("stage plan does not match the supplied handoff")
        if self.initial_checkpoint is not None:
            manifest = checkpoints.validate(self.initial_checkpoint, compatibility=self.compatibility,
                                            restart=True, restart_to=plan.sequence[0])
            if manifest["boundary"] != plan.source_boundary:
                raise ValueError("stage sequence initial boundary does not match checkpoint")

    def run_segment(self, boundary, *, checkpoint=None):
        """Useful standalone API; returns mutable candidate, never claims readiness."""
        if boundary not in BOUNDARIES or (boundary == "synthesis") != (checkpoint is None):
            raise ValueError("physical segments require an explicit tested checkpoint")
        source_boundary = None
        if checkpoint is not None:
            manifest = checkpoints.validate(checkpoint, compatibility=self.compatibility,
                                            restart=True, restart_to=boundary)
            source_boundary = manifest["boundary"]
        bridge = self.project / "bridge/librelane_bridge.py"
        if checkpoints.digest(bridge) != self.compatibility["bridge_sha256"]:
            raise ValueError("transported bridge changed")
        tag = boundary + "-" + uuid.uuid4().hex
        candidate = self.project / "candidates" / tag
        candidate.parent.mkdir(exist_ok=True)
        request = {"boundary": boundary, "checkpoint": str(checkpoint) if checkpoint else None,
                   "source_boundary": source_boundary,
                   "candidate": str(candidate), "project": str(self.project),
                   "pdk_root": str(self.pdk_root), "tag": tag,
                   "bridge_sha256": self.compatibility["bridge_sha256"]}
        request_path = self.project / (tag + "-request.json")
        request_path.write_text(checkpoints.canonical(request) + "\n")
        code = self.launch(bridge, request_path, tag)
        if code:
            return SegmentResult(boundary, candidate, "failed", code)
        report = checkpoints.read(candidate / "segment.json")
        if (report.get("status") != "completed" or report.get("boundary") != boundary
                or report.get("bridge_sha256") != self.compatibility["bridge_sha256"]):
            raise ValueError("missing or inconsistent outer segment completion")
        return SegmentResult(boundary, candidate, "completed", 0)

    def invoke(self, action, *, best_effort=False):
        return self.run_segment(action.stage, checkpoint=(self.current_checkpoint
                                                         if action.stage != "synthesis" else None))

    def publish(self, action, result):
        if result.exit_code or result.status != "completed" or result.boundary != action.stage:
            raise ValueError("unsuccessful segment cannot be published")
        def validate_runtime(candidate):
            bridge = self.project / "bridge/librelane_bridge.py"
            if checkpoints.digest(bridge) != self.compatibility["bridge_sha256"]:
                raise ValueError("transported publication validator changed")
            tag = "validate-" + result.boundary + "-" + uuid.uuid4().hex
            request = {"mode": "validate_publication", "candidate": str(candidate),
                       "boundary": result.boundary, "project": str(self.project),
                       "pdk_root": str(self.pdk_root), "bridge_sha256": self.compatibility["bridge_sha256"]}
            request_path = self.project / (tag + "-request.json")
            request_path.write_text(checkpoints.canonical(request) + "\n")
            if self.launch(bridge, request_path, tag):
                raise ValueError("runtime closure validation failed; checkpoint not published")

        artifact = checkpoints.publish(result.candidate, self.checkpoint_store,
                                       compatibility=self.compatibility, boundary=result.boundary,
                                       validate_runtime=validate_runtime)
        self.current_checkpoint = artifact["path"]
        return artifact


def prepare(*, bundle, support_tools, pdk_root, python, workspace, checkpoint_store,
            initial_checkpoint=None, timeout=600, preflight_output=None):
    """Explicit host composition service. Docker-only demonstrated capability.

    Fresh workspace for a new recipe; resume uses the retained path-bound workspace.
    Published stores must be in the mounted workspace. Native/relocated/macro
    checkpoints are intentionally not advertised.
    """
    bundle, support_tools, pdk_root = (Path(p).resolve() for p in (bundle, support_tools, pdk_root))
    workspace, checkpoint_store = Path(workspace).absolute(), Path(checkpoint_store).absolute()
    if not checkpoint_store.is_relative_to(workspace):
        raise ValueError("checkpoint store must be under the explicitly mounted workspace")
    if timeout <= 0:
        raise ValueError("segment timeout must be positive")
    probe = lambda: phase4.preflight(bundle, support_tools, pdk_root, Path(python).absolute())
    if preflight_output is None:
        report = probe()
    else:
        checked = result_store.durable_preflight(bundle, preflight_output, probe)
        if checked.status == "interrupted":
            raise result_store.FlowInterrupted(checked.exit_code - 128)
        report = checked.result
    if not report["ready"]:
        raise ValueError(f"stage preflight failed: {report['issues']}")
    binding = transport.from_preflight(report, native=False)
    transport.verify_engine(binding)
    transport.verify_image(binding)
    if binding["image_identity"]["image_id"] != TESTED_IMAGE:
        raise ValueError("explicit physical stages have only been tested with the declared exact image")
    project = workspace / "project"
    manifest = phase4.read_json(bundle / "manifest.json")
    bridge_source = Path(__file__).with_name("librelane_bridge.py")
    compatibility = {"bundle_identity": manifest["identity"], "target": manifest["target"],
                     "requested_tools": manifest["requested_tools"], "binding": binding,
                     "bridge_sha256": checkpoints.digest(bridge_source), "project": str(project),
                     "pdk_root": str(pdk_root)}
    if initial_checkpoint is None:
        workspace.mkdir()  # no overwrite of existing user work
        shutil.copytree(bundle, project)
        for ref in manifest["target"]["external_references"]:
            if ref["source"] == "Support_tools":
                source = phase4.safe_child(support_tools, ref["path"])
                target = phase4.safe_child(project / "tt", ref["path"])
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
        (project / "bridge").mkdir()
        shutil.copyfile(bridge_source, project / "bridge/librelane_bridge.py")
        checkpoint_store.mkdir(parents=True)
    else:
        checkpoints.validate(initial_checkpoint, compatibility=compatibility, restart=True)
    # One immutable image identity per run; no per-segment preflight/tag resolution.
    record = {"binding": binding, "commands": [], "bridge_sha256": compatibility["bridge_sha256"]}
    record_path = workspace / ("transport-" + uuid.uuid4().hex + ".json")
    phase4.save(record_path, record)
    phase4.save(workspace / (record_path.stem + "-preflight.json"), report)

    def launch(bridge, request, tag):
        name = transport.owned_name()
        transport.verify_engine(binding)
        transport.verify_image(binding)
        argv = transport.docker_command(binding, workspace, pdk_root, name=name,
                                        workdir=project, pdk=manifest["target"]["technology"])
        argv += [*binding["interpreter_flags"], str(bridge), str(request)]
        return phase4.run_logged(argv, project, transport.environment(), workspace / (tag + ".log"),
                                 record, record_path, timeout=timeout,
                                 cleanup=lambda: transport.cleanup(binding, name))

    adapter = SegmentAdapter(project=project, pdk_root=pdk_root, compatibility=compatibility,
                           launch=launch, checkpoint_store=checkpoint_store,
                           initial_checkpoint=initial_checkpoint)
    adapter.runtime_record = record_path
    return adapter
