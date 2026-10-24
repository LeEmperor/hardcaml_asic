# SRAM capability investigation

This track is independent of the flop-backed development example and provider
observation work. It does not reopen ASIC M3 or block ASIC P6 by default.

**Start with [the checkpoint](sram-status.md).** ASIC S.1 inventory and S.2a
functional-model checks are complete. S.3 established qualified local feasibility.
On 2026-10-23 the organizers' update email resolved macro eligibility: IHP SRAM
macros are allowed, several per design, if they fit and pass TT precheck. The
project support-tools pin now includes the SRAM marker-layer precheck fix. S.4,
production backend support, is no longer blocked on authority but is still
unimplemented. Timed-model conformance remains open.

| Document | Purpose |
| --- | --- |
| [Candidate inventory](sram-candidate-investigation.md) | Exact macro, collateral, pins and initial capability findings |
| [Model conformance](sram-model-conformance.md) | Functional checks and the simulator's timed-model limitation |
| [Target compatibility](sram-target-compatibility.md) | Eligibility, supplies and submission-revision questions |
| [Flow feasibility](sram-flow-feasibility.md) | Original bounded physical experiment and evidence |
| [S.3 disposition](sram-s3-disposition.md) | Later finding-by-finding interpretation, probe defects and follow-ups |

Read the disposition with the original feasibility result: it qualifies the
earlier summaries without changing their historical evidence. Actual macro
permission, accepted supply mapping and timed-model evidence remain separate
from successful local place-and-route. Recheck installed inputs before a new
experiment; historical scaf paths are not current prerequisites.

The portable [Single_port_ram contract](../reference/program-memory-contract.md)
stays in `reference/`: it governs behavioral/flop implementations too, not only SRAM.
