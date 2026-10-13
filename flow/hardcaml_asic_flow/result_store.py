"""Exclusive result allocation and bounded, durable readiness diagnostics.

Roots are caller-owned choices. These records are neither implementation runs
nor a producer observation journal. Atomic replacement does not promise fsync
or recovery of observations from a crashed probe.
"""

from __future__ import annotations

import contextlib
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import tempfile
import uuid


def utc_now():
    return datetime.now(timezone.utc)


def timestamp(clock):
    value = clock()
    if value.tzinfo is None:
        raise ValueError("result-store clock must be timezone-aware")
    return value.astimezone(timezone.utc)


@dataclass(frozen=True)
class Allocation:
    identity: str
    directory: Path
    created_at: str


def allocate(root, *, clock=utc_now, id_factory=uuid.uuid4, max_attempts=8):
    """Reserve a new child exclusively; collisions retry at most max_attempts."""
    if max_attempts < 1:
        raise ValueError("max_attempts must be positive")
    root = Path(root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    for _ in range(max_attempts):
        instant = timestamp(clock)
        identity = uuid.UUID(str(id_factory())).hex
        name = instant.strftime("%Y%m%dT%H%M%S%fZ") + "_" + identity[:8]
        directory = root / name
        try:
            directory.mkdir(exist_ok=False)
        except FileExistsError:
            continue
        return Allocation(identity, directory, instant.isoformat())
    raise FileExistsError(f"result allocation exhausted {max_attempts} attempts under {root}")


def save_json(path, value):
    """Atomically replace a JSON file; its parent must already exist."""
    path = Path(path)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary)
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write(json.dumps(value, indent=2, sort_keys=True) + "\n")
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


class FlowInterrupted(Exception):
    def __init__(self, signum):
        super().__init__(f"interrupted by {signal.Signals(signum).name}")
        self.signum = signum


def interrupt_handler(signum, _frame):
    raise FlowInterrupted(signum)


@contextlib.contextmanager
def interruption_handlers():
    previous = {}
    try:
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous[signum] = signal.signal(signum, interrupt_handler)
        yield
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


def diagnostic(bundle, status, issue, *, provenance=None, signum=None):
    details = dict(provenance or {})
    details.update(status=status, bundle=str(Path(bundle).resolve()))
    if signum is not None:
        details["interrupted_by"] = signal.Signals(signum).name
    return {"ready": False, "issues": [issue], "diagnostic": details}


@dataclass(frozen=True)
class PreflightResult:
    report_path: Path
    result: dict
    status: str
    exit_code: int


def durable_preflight(bundle, report_path, probe, *, save=save_json, provenance=None):
    """Publish pending before calling probe(), then its exact report or a diagnostic.

    Destination/publication errors propagate. Probe exceptions and scoped signals
    become failed/interrupted reports, with no invented partial observations.
    """
    report_path = Path(report_path).absolute()
    with interruption_handlers():
        try:
            save(report_path, diagnostic(bundle, "pending", "preflight pending; tool probes have not completed",
                                         provenance=provenance))
            try:
                result = probe()
                if (not isinstance(result, dict) or type(result.get("ready")) is not bool
                        or not isinstance(result.get("issues"), list)):
                    raise ValueError("malformed preflight result: expected ready boolean and issues list")
                status, exit_code = ("ready", 0) if result["ready"] else ("failed", 1)
            except FlowInterrupted:
                raise
            except Exception as exc:
                status, exit_code = "failed", 1
                result = diagnostic(bundle, status, f"preflight failed: {type(exc).__name__}: {exc}",
                                    provenance=provenance)
            save(report_path, result)
        except (FlowInterrupted, KeyboardInterrupt) as exc:
            signum = exc.signum if isinstance(exc, FlowInterrupted) else signal.SIGINT
            status, exit_code = "interrupted", 128 + signum
            result = diagnostic(bundle, status, f"interrupted by {signal.Signals(signum).name}",
                                provenance=provenance, signum=signum)
            save(report_path, result)
    return PreflightResult(report_path, result, status, exit_code)


def validate_output(path):
    """Validate an explicit file without creating its parent or probing tools."""
    path = Path(path).absolute()
    if not path.parent.is_dir():
        raise FileNotFoundError(f"preflight output parent does not exist: {path.parent}")
    if path.is_dir():
        raise IsADirectoryError(f"preflight output is a directory: {path}")
    if not os.access(path.parent, os.W_OK | os.X_OK) or (
            path.exists() and not os.access(path, os.W_OK)):
        raise PermissionError(f"preflight output is not writable: {path}")
    return path


@dataclass(frozen=True)
class PreflightOutcome:
    receipt: dict | None
    receipt_path: Path | None
    report_path: Path
    result: dict
    status: str
    exit_code: int


def preflight_operation(bundle, *, results_root, probe, output=None, save=save_json,
                        clock=utc_now, id_factory=uuid.uuid4, max_attempts=8,
                        provenance=None):
    """Run a standalone diagnostic, returning rendering-neutral paths and status.

    Default: results_root/operations/<allocation>/{operation,preflight}.json.
    Explicit output: only that file, no receipt or operation directory.
    The zero-argument probe callback owns all readiness policy.
    """
    bundle = Path(bundle).resolve()
    if output is not None:
        path = validate_output(output)
        checked = durable_preflight(bundle, path, probe, save=save, provenance=provenance)
        return PreflightOutcome(None, None, path, checked.result, checked.status, checked.exit_code)
    allocation = allocate(Path(results_root) / "operations", clock=clock,
                          id_factory=id_factory, max_attempts=max_attempts)
    path = allocation.directory / "preflight.json"
    receipt_path = allocation.directory / "operation.json"
    receipt = {"schema_version": 1, "record_type": "preflight_operation",
               "operation_id": allocation.identity, "bundle": str(bundle),
               "started_at": allocation.created_at, "ended_at": None,
               "status": "pending", "report": "preflight.json", "exit_code": None}
    save(receipt_path, receipt)
    try:
        checked = durable_preflight(bundle, path, probe, save=save, provenance=provenance)
        receipt.update(status=checked.status, exit_code=checked.exit_code)
    except BaseException as exc:
        signum = None
        if isinstance(exc, FlowInterrupted):
            signum = exc.signum
        elif isinstance(exc, KeyboardInterrupt):
            signum = signal.SIGINT
        receipt.update(status="interrupted" if signum else "failed",
                       exit_code=128 + signum if signum else 1, error=str(exc))
        raise
    finally:
        receipt["ended_at"] = timestamp(clock).isoformat()
        save(receipt_path, receipt)
    return PreflightOutcome(receipt, receipt_path, path, checked.result, checked.status, checked.exit_code)
