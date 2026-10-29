"""Pure model derivation tests. No simulator or native EDA executable is run."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest


def load_runtime(path):
    spec = importlib.util.spec_from_file_location("production_physical_models", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def save(path, value):
    path.write_text(json.dumps(value) + "\n")


def fixture(root, runtime, pdk=None):
    supplied_pdk = pdk is not None
    project, output = root / "project", root / "output"
    project.mkdir(); output.mkdir()
    if pdk is None:
        pdk = root / "pdk"
        cells = pdk / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog"
        cells.mkdir(parents=True)
        (cells / "sg13cmos5l_stdcell.v").write_bytes(Path(__file__).with_name("vendor_cells.v").read_bytes())
        (cells / "sg13cmos5l_udp.v").write_text("// supplied UDP fixture retained byte-for-byte\n")
    cells = pdk / "ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/verilog"
    vendor, udp = cells / "sg13cmos5l_stdcell.v", cells / "sg13cmos5l_udp.v"
    marker = dict(schema_version=1, resolution_policy="scalar-q-driver-cmos5l-physical-v2", analysis_corners="all_configured",
        analysis_stages=["synthesized_netlist", "post_pnr"], sequential_inventory="exact_declared_stages", max_buffer_hops=8,
        endpoint_map="::hc_pt7::checked_endpoints", trace_inventory="::hc_pt7::checked_traces")
    save(project / "manifest.json", dict(top_module="top", operation="Hardening", target=dict(technology="ihp-sg13cmos5l"),
         timing_intent=dict(resolution_policy=marker["resolution_policy"]), timing_physical_qualification=marker))
    save(root / "preflight.json", dict(references=[dict(path=str(p.resolve()), sha256=runtime.sha(p)) for p in (vendor, udp)]))
    netlist = project / "runs/asic/final/nl/top.nl.v"
    netlist.parent.mkdir(parents=True)
    names = ["sg13cmos5l_dfrbpq_1", "sg13cmos5l_dfrbpq_2", "sg13cmos5l_dfrbp_1", "sg13cmos5l_dfrbp_2", "sg13cmos5l_buf_1"]
    if supplied_pdk:
        names += ["sg13cmos5l_buf_2", "sg13cmos5l_buf_4", "sg13cmos5l_buf_8", "sg13cmos5l_buf_16",
                  "sg13cmos5l_dlygate4sd1_1", "sg13cmos5l_dlygate4sd2_1", "sg13cmos5l_dlygate4sd3_1",
                  "sg13cmos5l_and2_1", "sg13cmos5l_and2_2", "sg13cmos5l_tiehi", "sg13cmos5l_tielo"]
    netlist.write_text("\n".join(f"{name} cell_{i} (.Q(q));" for i, name in enumerate(names)) + "\n")
    return project, pdk, netlist, output, vendor, udp


class ModelReplay(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="functional-model-profile ")
        self.root = Path(self.temp.name)
        self.project, self.pdk, self.netlist, self.output, self.vendor, self.udp = fixture(self.root, RUNTIME)

    def tearDown(self):
        self.temp.cleanup()

    def replay(self):
        RUNTIME.replay_models(self.project, self.pdk, self.netlist, self.output)

    def rebind_vendor(self):
        save(self.root / "preflight.json", dict(references=[dict(path=str(p.resolve()), sha256=RUNTIME.sha(p)) for p in (self.vendor, self.udp)]))

    def test_used_only_exact_source_and_sizing(self):
        before = {p: p.read_bytes() for p in (self.vendor, self.udp, self.netlist)}
        self.replay()
        view = (self.output / "stdcell-functional.v").read_text()
        self.assertNotIn("specify", view)
        self.assertNotIn("module sg13cmos5l_unreviewed_1", view)
        for pin in ("CLK", "D", "RESET_B"):
            self.assertEqual(view.count(f"assign delayed_{pin} = {pin};"), 4)
        self.assertEqual((self.output / "stdcell-vendor.v").read_bytes(), before[self.vendor])
        self.assertEqual((self.output / "model-0.v").read_bytes(), before[self.udp])
        self.assertTrue(all(p.read_bytes() == value for p, value in before.items()))
        inventory = json.loads((self.output / "replay-models.json").read_text())
        self.assertEqual(inventory["profile"], "cmos5l_physical_timing_used_cells_v1")
        self.assertIn("not_vendor_timing_or_sdf", inventory["claim"])
        self.assertEqual(inventory["netlist_sha256"], RUNTIME.sha(self.netlist))
        self.assertEqual(len(inventory["vendor_module_sha256"]), 5)
        for name, digest in inventory["retained_hashes"].items():
            self.assertEqual(RUNTIME.sha(self.output / name), digest)

    def test_changed_supplied_vendor_is_not_adapted(self):
        self.vendor.write_text(self.vendor.read_text() + "// changed\n")
        with self.assertRaisesRegex(ValueError, "run-bound standard-cell model changed"):
            self.replay()

    def test_changed_udp_is_not_adapted(self):
        self.udp.write_text("changed UDP\n")
        with self.assertRaisesRegex(ValueError, "run-bound standard-cell model changed"):
            self.replay()

    def test_hash_consistent_wrong_reset_function_rejects(self):
        self.vendor.write_text(self.vendor.read_text().replace("not (int_fwire_r, delayed_RESET_B)", "buf (int_fwire_r, delayed_RESET_B)"))
        self.rebind_vendor()
        with self.assertRaisesRegex(ValueError, "unreviewed reset-flop functional body"):
            self.replay()

    def test_hash_consistent_extra_delayed_driver_rejects(self):
        self.vendor.write_text(self.vendor.read_text().replace("buf (Q, int_fwire_IQ);", "buf (Q, int_fwire_IQ); assign delayed_CLK=1'b0;"))
        self.rebind_vendor()
        with self.assertRaisesRegex(ValueError, "unreviewed reset-flop functional body"):
            self.replay()

    def test_unknown_delayed_cell_rejects(self):
        self.netlist.write_text("sg13cmos5l_unreviewed_1 u (.Q(q));\n")
        with self.assertRaisesRegex(ValueError, "unreviewed nonstructural/delayed-reference"):
            self.replay()

    def test_unknown_cell_rejects(self):
        self.netlist.write_text("sg13cmos5l_unknown_1 u (.Q(q));\n")
        with self.assertRaisesRegex(ValueError, "unknown/nonunique vendor cell"):
            self.replay()

    def test_duplicate_definition_rejects(self):
        self.vendor.write_text(self.vendor.read_text() + "\nmodule sg13cmos5l_buf_1(X,A); output X; input A; buf(X,A); endmodule\n")
        self.rebind_vendor()
        with self.assertRaisesRegex(ValueError, "unknown/nonunique vendor cell"):
            self.replay()

    def test_other_netlist_path_rejects(self):
        path = self.root / "substitute.v"
        path.write_bytes(self.netlist.read_bytes())
        with self.assertRaisesRegex(ValueError, "unchanged final implementation netlist"):
            RUNTIME.replay_models(self.project, self.pdk, path, self.output)

    def test_ineligible_profile_rejects(self):
        path = self.project / "manifest.json"
        manifest = json.loads(path.read_text())
        manifest["timing_physical_qualification"]["max_buffer_hops"] = 99
        save(path, manifest)
        with self.assertRaisesRegex(ValueError, "unsupported macro-free timing replay profile"):
            self.replay()

    def test_output_is_not_reused(self):
        self.replay()
        before = (self.output / "replay-models.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "fresh timing replay output"):
            self.replay()
        self.assertEqual((self.output / "replay-models.json").read_bytes(), before)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--pdk-root", type=Path)
    args = parser.parse_args()
    RUNTIME = load_runtime(args.runtime)
    if args.pdk_root:
        # Explicit supplied-source structural qualification only, no simulation.
        with tempfile.TemporaryDirectory(prefix="supplied-functional-source ") as tmp:
            project, pdk, netlist, output, vendor, udp = fixture(Path(tmp), RUNTIME, args.pdk_root)
            before = {p: RUNTIME.sha(p) for p in (vendor, udp)}
            RUNTIME.replay_models(project, pdk, netlist, output)
            assert all(RUNTIME.sha(p) == digest for p, digest in before.items())
            print(json.dumps(dict(status="passed_structural_only_no_simulator", supplied_sources={str(p): h for p, h in before.items()},
                  used_cell_types=sorted(json.loads((output / "replay-models.json").read_text())["adaptations"]))))
    else:
        unittest.main(argv=[__file__])
