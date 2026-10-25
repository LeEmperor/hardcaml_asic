# SRAM capability investigation

This directory retains SRAM investigation detail and evidence. Production SRAM
support is now a priority in the [active ASIC PT.0–PT.2 queue](../phase_plan.md#active-queue),
followed by Protemu acceptance and resource inspection. The earlier feasibility
records retain their qualifications; this does not reopen completed ASIC M3 work.

**Start with [the checkpoint](sram-status.md).** ASIC S.1 inventory and S.2a
functional-model checks are complete. S.3 established qualified local feasibility.
PT.0a/b have corrected power-access and corner-binding evidence. PT.0c is now
dispositioned through the accepted public example physical path; the original
probe's qualifications remain historical. See the [physical closeout](../development/sram-example-physical.md).
On 2026-10-23 the organizers' update email resolved macro eligibility: IHP SRAM
macros are allowed, several per design, if they fit and pass TT precheck. The
project support-tools pin now includes the SRAM marker-layer precheck fix. S.4
now has public exact-macro and fresh synthesis/full support demonstrated by the
independent example. Timed-model conformance remains open; physical acceptance
uses the explicit real-GDS/abstract-macro-boundary checking scope in the closeout.

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
