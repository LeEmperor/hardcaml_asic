"""Shared coarse lifecycle runner and adapter to the existing flow services.

No presentation or tool/runtime resolution lives here. Occurrences are an
in-memory attempt snapshot; optional lifecycle consumers own persistence. Collection is
best effort after implementation/verification failure; its result never promotes
that failure to success. Acceptance is a separate service verdict.
"""

from dataclasses import dataclass, field
import signal
import time
from types import SimpleNamespace
import uuid

from .execution_plan import Plan, StagePlan
from .result_store import interruption_handlers


@dataclass
class Occurrence:
    occurrence_id: str
    action_key: str
    status: str = "unreached"
    exit_code: int | None = None
    duration_seconds: float = 0
    best_effort: bool = False
    error: str | None = None
    verdict: str | None = None

    def as_dict(self):
        return dict(vars(self))


@dataclass
class Execution:
    attempt_id: str
    plan: Plan
    occurrences: list[Occurrence]
    status: str = "completed"
    exit_code: int = 0
    run_outcome: object = None
    steps: list[dict] = field(default_factory=list)
    archive: str | None = None
    artifacts: list[dict] = field(default_factory=list)

    def as_dict(self):
        value = {"attempt_id": self.attempt_id, "plan": self.plan.as_dict(),
                "occurrences": [item.as_dict() for item in self.occurrences],
                 "status": self.status, "exit_code": self.exit_code}
        if self.artifacts:
            value["artifacts"] = self.artifacts
        if self.run_outcome is not None:
            value["run"] = self.run_outcome.as_dict()
        if self.archive is not None:
            value["archive"] = self.archive
        return value


class ServiceAdapter:
    """Bind existing services to a resolved plan, without mutating caller args."""

    def __init__(self, args, operations):
        self.args = args
        self.operations = operations
        self.run_outcome = None

    def validate(self, plan):
        if plan.endpoint != self.args.stage or plan.actions[-1].enabled != (self.args.archive is not None):
            raise ValueError("plan does not match the bound service inputs")

    def invoke(self, action, *, best_effort=False):
        if action.operation == "run":
            self.run_outcome = self.operations.run(self.args)
            return self.run_outcome
        run_dir = self.run_outcome.run_dir
        if action.operation == "postcheck":
            values = vars(self.args).copy()
            values["run_dir"] = run_dir
            args = SimpleNamespace(**values)
        elif action.operation == "collect":
            args = SimpleNamespace(run_dir=run_dir, output=run_dir / "results.json",
                                   stdout=False, quiet=True, json=False,
                                   verbose=self.args.verbose)
        elif action.operation == "report":
            args = SimpleNamespace(run_dir=run_dir, json=False,
                                   diagnostics_only=True, verbose=self.args.verbose)
        else:
            args = SimpleNamespace(run_dir=run_dir, output=self.args.archive,
                                   list=False, force=self.args.force, quiet=True)
        return getattr(self.operations, action.operation)(args)


def execute(plan, adapter, *, observe=None, lifecycle=None, attempt_id=None, clock=time.monotonic):
    """Run a coarse plan with scoped SIGINT/SIGTERM handling."""
    with interruption_handlers():
        return _execute(plan, adapter, observe=observe, lifecycle=lifecycle, attempt_id=attempt_id, clock=clock)


def _execute(plan, adapter, *, observe=None, lifecycle=None, attempt_id=None, clock=time.monotonic):
    """Execute the bounded plan; observe(action, outcome) is presentation only.

    Preallocation implementation exceptions propagate to the command boundary:
    without a returned run, there is no owned directory to collect. The existing
    implementation service records failures/signals after allocation and returns
    their run identity. All subsequent service exceptions become occurrence facts.
    """
    if not isinstance(plan, (Plan, StagePlan)):
        raise ValueError("expected a validated coarse execution plan")
    adapter.validate(plan)
    attempt_id = attempt_id or uuid.uuid4().hex
    occurrences = [Occurrence(f"{attempt_id}/{action.key}", action.key,
                              status="unreached" if action.enabled else "skipped")
                   for action in plan.actions]
    execution = Execution(attempt_id, plan, occurrences)
    stopped = False
    for action, occurrence in zip(plan.actions, occurrences):
        if not action.enabled:
            continue
        best_effort = stopped and action.gate == "run_available" and execution.run_outcome is not None
        if stopped and not best_effort:
            continue
        started = clock()
        occurrence.status = "running"
        occurrence.best_effort = best_effort
        if lifecycle is not None:
            lifecycle("started", action, occurrence.as_dict(), None)
        outcome = None
        try:
            outcome = adapter.invoke(action, best_effort=best_effort)
            if action.operation == "run":
                execution.run_outcome = outcome
            code = outcome.exit_code if action.operation in ("run", "postcheck", "segment") else outcome
            status = (outcome.status if action.operation in ("run", "postcheck", "segment") else
                      ("accepted" if code == 0 else "rejected") if action.operation == "report" else
                       "completed" if code == 0 else "failed")
            if action.operation == "segment" and not code:
                # Publication is part of the occurrence: no ready fact can precede
                # complete validation and atomic promotion out of mutable work.
                artifact = adapter.publish(action, outcome)
                execution.artifacts.append(artifact)
                if lifecycle is not None:
                    lifecycle("published", action, occurrence.as_dict(), artifact)
            occurrence.status = "completed" if status in ("accepted", "rejected") else status
            if action.operation == "report":
                occurrence.verdict = status
        except (Exception, KeyboardInterrupt) as exc:
            if action.operation == "run":
                raise
            signum = signal.SIGINT if isinstance(exc, KeyboardInterrupt) else getattr(exc, "signum", None)
            code = 128 + signum if signum is not None else 2
            status = "interrupted" if signum is not None else "failed"
            occurrence.status = status
            occurrence.error = str(exc)
        occurrence.exit_code = code
        occurrence.duration_seconds = round(clock() - started, 6)
        step = {"operation": action.operation, "status": status, "exit_code": code,
                "duration_seconds": occurrence.duration_seconds}
        if best_effort:
            step["best_effort"] = True
        if occurrence.error is not None:
            step["error"] = occurrence.error
        execution.steps.append(step)
        if lifecycle is not None:
            lifecycle("finished", action, occurrence.as_dict(),
                      execution.artifacts[-1] if action.operation == "segment" and not code else None)
        if code and not best_effort:
            execution.status, execution.exit_code = status, code
            stopped = True
        if action.operation == "archive" and not code:
            execution.archive = str(adapter.args.archive)
        if observe is not None and outcome is not None and action.operation == "postcheck":
            observe(action, outcome)
    return execution
