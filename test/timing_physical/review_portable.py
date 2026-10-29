"""Final bounded archive/package review. Read-only evidence; no EDA/builds."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

ASIC = Path(__file__).resolve().parents[2]
EXAMPLE = ASIC.parent / "hardcaml_asic_example"
AREA = EXAMPLE / ".dev/asic-timing-physical"
RUN = AREA / "full-runs/20261029T075052976305Z_23a6954b"
EVIDENCE = AREA / "evidence"
ARCHIVE = EVIDENCE / "full-public-corrected-01/archive-output"
RESTORE = EVIDENCE / "full-restore-corrected-01"
RESTORED = RESTORE / "restored"
PACKAGE = EVIDENCE / "portable-package-01"
GENERATIONS = AREA / "provider/generations"
OLD = GENERATIONS / "4856e6af993642988c18c07f47a8c689"
NEW = GENERATIONS / "1ba205c2a11c4904b03d98b0e7a3f616"
OUT = Path(tempfile.mkdtemp(prefix="timing-physical-portable-review-", dir="/tmp/opencode"))
HASHES = {}
COUNT = 0

def sha(path):
    with Path(path).open("rb") as stream:
        value = hashlib.file_digest(stream, "sha256").hexdigest()
    HASHES[str(path)] = value
    return value

def read(path):
    sha(path)
    return json.loads(Path(path).read_text())

def check(value, label):
    global COUNT
    assert value, label
    COUNT += 1

closeout = read(PACKAGE / "closeout.json")
for key in ("execution_provider", "corrected_archiver_provider", "portable_verification", "prior_documentation_snapshot", "source_inventory", "package"):
    reference = closeout[key]
    check(sha(reference["path"]) == reference["sha256"], key)
for name, reference in closeout["public_archive"].items():
    check(sha(ARCHIVE / name) == reference["sha256"], "archive component " + name)
check(read(OLD / "receipt.json")["snapshot_sha256"] == "4a821a382619f33eda6be911cb1bddc9d71345a882e97c5fb5b5de68979153a3", "execution capture")
check(read(NEW / "receipt.json")["snapshot_sha256"] == closeout["corrected_reader_snapshot_sha256"], "archiver capture")
archive_source = "lib/hardcaml_asic/execution/archive/archive_service.ml"
check(sha(NEW / archive_source) == closeout["corrected_archive_source_sha256"] == "4c86b6516f31b0c1c18a07364ab85b7c38a9122633debec2cafeac93befb415d", "corrected archive source")

before = read(EVIDENCE / "portable-before-01/snapshot.json")["run_before"]["files"]
check(len(before) == 1196, "original run file count")
for relative, digest in before.items():
    check(sha(RUN / relative) == digest, "unchanged original " + relative)

descriptor = read(ARCHIVE / "archive.json")
check(len(descriptor["members"]) == 449, "449 archive members")
tar_hashes = {}
with tarfile.open(ARCHIVE / "reports.tar.gz") as stream:
    for member in stream:
        check(member.isfile(), "regular report tar member")
        digest = hashlib.file_digest(stream.extractfile(member), "sha256").hexdigest()
        check(member.name not in tar_hashes and digest == before[member.name], "exact original tar member " + member.name)
        check(sha(RESTORED / member.name) == digest, "exact restored tar member " + member.name)
        tar_hashes[member.name] = digest
check(set(tar_hashes) == set(descriptor["members"]), "descriptor/tar complete member equality")
with tarfile.open(ARCHIVE / "input-bundle.tar.gz") as stream:
    for member in stream:
        check(member.isfile() and member.name.startswith("bundle/"), "bundle tar member")
        relative = member.name.removeprefix("bundle/")
        digest = hashlib.file_digest(stream.extractfile(member), "sha256").hexdigest()
        check(digest == sha(RUN / "project" / relative) == sha(RESTORED / "project" / relative), "bundle/restored/original bytes " + relative)
for name in ("run.json", "preflight.json"):
    check(sha(ARCHIVE / name) == sha(RESTORED / name) == sha(RUN / name), "loose record " + name)
check(sha(ARCHIVE / "postcheck.json") == sha(RESTORED / "checks/bc95939552ae415c9a5aaa8c1fff1cfe/postcheck.json"), "exact loose postcheck restored")

original = read(EVIDENCE / "full-public-01/collect/stdout.log")
artifacts = original["raw_artifacts"]
check(len(artifacts) == len(set(artifacts)) == 423, "423 unique original raw artifacts")
for relative in artifacts:
    check(sha(RESTORED / relative) == sha(RUN / relative) == before[relative], "all original raw artifacts restored " + relative)
seven = ["project/runs/asic/" + name for name in (
    "40-openroad-checkantennas/reports/antenna.rpt", "40-openroad-checkantennas/reports/antenna_summary.rpt",
    "46-openroad-checkantennas-1/reports/antenna.rpt", "46-openroad-checkantennas-1/reports/antenna_summary.rpt",
    "62-magic-drc/reports/drc.magic.rpt", "66-netgen-lvs/reports/lvs.netgen.json", "66-netgen-lvs/reports/lvs.netgen.rpt")]
check(all(path in artifacts and path in tar_hashes for path in seven), "all seven fixed reports included")

# Re-execute only the three recorded read-only readers in the same hidden-source,
# read-only namespace; this invokes no tools/EDA and creates no restored files.
for name, code in (("inspect", 1), ("collect", 0), ("report", 0)):
    receipt = read(RESTORE / name / "command.json")
    args = receipt["argv"]
    check(args[0] == "bwrap" and "--unshare-net" in args and "--tmpfs" in args, "recorded hidden-input reader")
    check(str(NEW / "bin/hardcaml-asic-flow") in args, "corrected reader executable")
    p = subprocess.run(args, cwd="/tmp/opencode", text=True, capture_output=True, timeout=180)
    (OUT / (name + ".stdout")).write_text(p.stdout)
    (OUT / (name + ".stderr")).write_text(p.stderr)
    check(p.returncode == code, (name, p.returncode, p.stderr))
    value = json.loads(p.stdout)
    expected = read(EVIDENCE / "full-public-01" / name / "stdout.log")
    check(value == expected == read(RESTORE / name / "stdout.log"), "exact original/restored public response " + name)
    if name != "inspect":
        check(value["raw_artifacts"] == artifacts, "exact 423 list " + name)

package_hashes = {}
with tarfile.open(closeout["package"]["path"]) as stream:
    for member in stream:
        if not member.isfile():
            continue
        relative = member.name.removeprefix("portable-source-closeout/")
        digest = hashlib.file_digest(stream.extractfile(member), "sha256").hexdigest()
        check(relative not in package_hashes and digest == closeout["package_inventory"][relative], "portable package inventory " + relative)
        package_hashes[relative] = digest
check(len(package_hashes) == 4269 and set(package_hashes) == set(closeout["package_inventory"]), "complete portable package inventory")

helper = "lib/hardcaml_asic/flow/hardcaml_asic_flow/timing_physical_runtime.py"
source_identity = dict(execution_helper=sha(OLD / helper), corrected_archive_helper=sha(NEW / helper),
    current_forward_helper=sha(ASIC / "flow/hardcaml_asic_flow/timing_physical_runtime.py"),
    execution_archive_source=sha(OLD / archive_source), corrected_archive_source=sha(NEW / archive_source))
contributions = {}
for corner in ("nom_fast_1p32V_m40C", "nom_typ_1p20V_25C", "nom_slow_1p08V_125C"):
    path = RUN / "timing-intent/corners" / corner / "downstream_min.rpt"
    sha(path)
    first = path.read_text().split("Startpoint:")[1]
    check("hold29/X (sg13cmos5l_dlygate4sd3_1)" in first and "0.250000" in first, "representative actual repaired hold witness")
    rows = [line.strip() for line in first.splitlines() if any(token in line for token in
        ("_06_/CLK", "_05_/CLK", "_06_/Q", "hold29/X", "data arrival time", "data required time", "clock uncertainty", "clock reconvergence", "library hold", "slack"))]
    contributions[corner] = rows

for path, digest in list(HASHES.items()):
    check(sha(path) == digest, "reviewed bytes unchanged " + path)
summary = dict(status="passed", assertions=COUNT, run_files_unchanged=len(before), archive_members=len(tar_hashes),
    original_raw_artifacts=len(artifacts), seven_reports={p: tar_hashes[p] for p in seven},
    package_files=len(package_hashes), package_sha256=closeout["package"]["sha256"], source_identity=source_identity,
    public_parity=dict(inspect=True, collect=True, report=True), representative_hold=contributions, hashes=HASHES)
(OUT / "review.json").write_text(json.dumps(summary, indent=2) + "\n")
print(json.dumps({k: v for k, v in summary.items() if k != "hashes"} | dict(directory=str(OUT)), indent=2))
