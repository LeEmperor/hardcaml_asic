"""Pure contract matrix: no probes, containers, provisioning, Git or EDA."""

import copy
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "flow"))
from hardcaml_asic_flow import runtime_contract as rc


def requested(ll="3.1.0.dev3"):
    return {"python": "3.11", "librelane": ll, "runtime_policy": {
        "schema_version": 1,
        "host": {"python": {"policy": "exact-minor", "version": "3.11"}},
        "implementation": {
            "native": {"policy": "host-runtime"},
            "dockerized": {
                "policy": "official-librelane-image",
                "image_ref": "ghcr.io/librelane/librelane:" + ll,
                "python": {"policy": "distribution-supported",
                           "requires_python": ">=3.10",
                           "supported_minors": ["3.10", "3.11", "3.12", "3.13", "3.14"]}}}}}


def lock_values():
    return dict(line.split("=", 1) for line in (ROOT / "toolchain.lock").read_text().splitlines()
                if line and not line.startswith("#"))


HOST = {"python_version": "3.11.17"}
CONTAINER = {"python_version": "3.13.13", "librelane_version": "3.1.0.dev3",
             "requires_python": ">=3.10"}


class RuntimeContractTest(unittest.TestCase):
    def test_new_policy_accepts_supported_container_and_records_roles(self):
        contract = rc.policy_from_requested(requested())
        result = rc.evaluate(contract, HOST, CONTAINER)
        self.assertEqual(result["issues"], [])
        self.assertEqual(result["waivers"], [])
        self.assertEqual([r["role"] for r in result["comparisons"]],
                         ["host", "container", "container", "container"])
        self.assertTrue(all(r["status"] == "pass" for r in result["comparisons"]))
        for minor in rc.SUPPORTED_MINORS:
            with self.subTest(minor=minor):
                self.assertFalse(rc.evaluate(contract, HOST,
                                 dict(CONTAINER, python_version=minor + ".0"))["issues"])

    def test_legacy_strictness_and_explicit_waiver(self):
        contract = rc.policy_from_requested({"python": "3.11", "librelane": "3.1.0.dev3"})
        self.assertEqual(contract["source"], "legacy")
        self.assertEqual(len(rc.evaluate(contract, HOST, CONTAINER)["issues"]), 1)
        waived = rc.evaluate(contract, HOST, CONTAINER, allow_python_mismatch=True)
        self.assertFalse(waived["issues"])
        self.assertEqual(len(waived["waivers"]), 1)
        self.assertEqual(waived["waivers"][0]["role"], "container")
        self.assertFalse(rc.evaluate(contract, HOST,
                                    dict(CONTAINER, python_version="3.11.9"))["issues"])
        host_waived = rc.evaluate(contract, {"python_version": "3.12.1"},
                                 dict(CONTAINER, python_version="3.11.9"),
                                 allow_python_mismatch=True)
        self.assertFalse(host_waived["issues"])
        self.assertEqual(host_waived["waivers"][0]["role"], "host")
        for malformed in ("3.13", "3.13.13rc1", "v3.13.13", None, True, 31313):
            result = rc.evaluate(contract, HOST, dict(CONTAINER, python_version=malformed),
                                 allow_python_mismatch=True)
            self.assertTrue(result["issues"])
            self.assertFalse(result["waivers"])

    def test_new_failures_never_waived(self):
        contract = rc.policy_from_requested(requested())
        cases = [(dict(HOST, python_version="3.12.0"), CONTAINER),
                 (dict(HOST, python_version=True), CONTAINER)]
        for field, values in {
            "python_version": ["3.9.20", "3.15.0", "4.10.0", "3.13", "3.13.13rc1",
                               "03.13.13", None, True, 31313],
            "librelane_version": ["3.1.0.dev2", None, True],
            "requires_python": [">=3.11", ">=3.10,<4", " >=3.10", None, True],
        }.items():
            cases.extend((HOST, dict(CONTAINER, **{field: v})) for v in values)
        for host, container in cases:
            with self.subTest(host=host, container=container):
                result = rc.evaluate(contract, host, container, allow_python_mismatch=True)
                self.assertTrue(result["issues"])
                self.assertFalse(result["waivers"])

    def test_native_skips_container(self):
        result = rc.evaluate(rc.policy_from_requested(requested()), HOST, native=True)
        self.assertFalse(result["issues"])
        self.assertEqual(len(result["comparisons"]), 1)
        self.assertTrue(rc.evaluate(rc.policy_from_requested(requested()),
                                   {"python_version": "3.13.13"}, native=True)["issues"])

    def test_invalid_declarations_fail_closed(self):
        cases = []

        def changed(path, value=None, delete=False):
            r = requested()
            obj = r
            for key in path[:-1]:
                obj = obj[key]
            if delete:
                del obj[path[-1]]
            else:
                obj[path[-1]] = value
            cases.append(r)

        for value in (None, [], True, "1"):
            changed(["runtime_policy"], value)
        for value in (True, "1", 2, 1.0):
            changed(["runtime_policy", "schema_version"], value)
        changed(["runtime_policy", "unexpected"], 1)
        changed(["runtime_policy", "host", "python", "version"], "3.12")
        changed(["runtime_policy", "host", "python", "policy"], "any")
        changed(["runtime_policy", "implementation", "native", "policy"], "container")
        docker = ["runtime_policy", "implementation", "dockerized"]
        changed(docker + ["image_ref"], "ghcr.io/librelane/librelane:3.1.0.dev2")
        changed(docker + ["policy"], "any-image")
        changed(docker + ["python", "policy"], "any")
        for value in (">=3.10,<4", "<>=3.10", True):
            changed(docker + ["python", "requires_python"], value)
        for value in ([], "3.10,3.11", ["3.10"] * 5,
                      ["3.10", "3.11", "3.12", "3.13", "3.15"],
                      ["3.10", "3.11", "3.12", "3.13", True],
                      ["3.10", "3.11", "3.12", "3.13", "3.14.0"]):
            changed(docker + ["python", "supported_minors"], value)
        # Every required policy field must be present, with no fallback.
        def missing_fields(obj, path):
            for key, value in obj.items():
                changed(path + [key], delete=True)
                if type(value) is dict:
                    missing_fields(value, path + [key])
        missing_fields(requested()["runtime_policy"], ["runtime_policy"])
        changed(["python"], True)
        changed(["librelane"], "not-a-version")
        for value in cases:
            with self.subTest(value=value):
                with self.assertRaises(rc.ContractError):
                    rc.policy_from_requested(value)

    def test_lock_mirrors_policy_and_never_overrides_bundle(self):
        lock = lock_values()
        self.assertEqual(rc.policy_from_lock(lock), rc.policy_from_requested(requested()))
        historical = requested("2.2.9")
        historical["python"] = "3.12"
        historical["runtime_policy"]["host"]["python"]["version"] = "3.12"
        contract = rc.policy_from_requested(historical)
        self.assertNotEqual(contract, rc.policy_from_lock(lock))
        result = rc.evaluate(contract, {"python_version": "3.12.4"},
                             dict(CONTAINER, librelane_version="2.2.9"))
        self.assertFalse(result["issues"])
        self.assertEqual(contract["librelane"], "2.2.9")
        for key in lock:
            if key.startswith("runtime_"):
                with self.subTest(key=key):
                    missing = dict(lock)
                    del missing[key]
                    with self.assertRaises(rc.ContractError):
                        rc.policy_from_lock(missing)
                    with self.assertRaises(rc.ContractError):
                        rc.policy_from_lock(dict(lock, **{key: True}))

    def test_normalization_is_deterministic_and_detached(self):
        r = requested()
        before = copy.deepcopy(r)
        r["runtime_policy"]["implementation"]["dockerized"]["python"]["supported_minors"].reverse()
        parsed = rc.policy_from_requested(r)
        self.assertEqual(parsed, rc.policy_from_requested(before))
        parsed["implementation"]["dockerized"]["python"]["supported_minors"].clear()
        self.assertEqual(len(r["runtime_policy"]["implementation"]["dockerized"]["python"]["supported_minors"]), 5)

    def test_evaluator_rejects_invalid_contracts_and_flags(self):
        contract = rc.policy_from_requested(requested())
        for host in (None, [], True):
            with self.assertRaises(rc.ContractError):
                rc.evaluate(contract, host, CONTAINER)
        with self.assertRaises(rc.ContractError):
            rc.evaluate(contract, HOST)
        for flag in (1, "true", None):
            with self.assertRaises(rc.ContractError):
                rc.evaluate(contract, HOST, CONTAINER, native=flag)
            with self.assertRaises(rc.ContractError):
                rc.evaluate(contract, HOST, CONTAINER, allow_python_mismatch=flag)
        for key, value in (("schema_version", True), ("source", "unknown"),
                           ("host", None), ("implementation", {})):
            with self.subTest(key=key):
                with self.assertRaises(rc.ContractError):
                    rc.evaluate(dict(contract, **{key: value}), HOST, CONTAINER)
        self.assertTrue(rc.evaluate(contract, {}, {}, allow_python_mismatch=True)["issues"])


if __name__ == "__main__":
    unittest.main()
