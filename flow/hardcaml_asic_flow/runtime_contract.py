"""Pure runtime contract parsing and evaluation; no probes or installed defaults.

Public normalized contract (JSON-compatible): {schema_version: 1, source:
"legacy"|"runtime-policy", librelane: str, host: {python: {policy, version}},
implementation: {native: {policy}, dockerized: {policy, image_ref, python}}}.
Legacy docker Python is exact-minor; new docker Python is distribution-supported.
The image_ref is an official mutable tag, NOT a cross-machine immutable identity.

evaluate takes host/container observations {python_version: "3.11.17",
librelane_version: "3.1.0.dev3", requires_python: ">=3.10"}. Host needs only
python_version; container metadata is mandatory for the new policy. Native skips
container observations. Results contain contract, native, issues, waivers and
comparisons (role, field, expected, actual, status: pass|fail|waived). No existing
flat actual keys or stored records are rewritten. Missing observations fail.

Only valid legacy exact-minor mismatches admit allow_python_mismatch. New explicit
host policy has no waiver, conservatively; malformed versions, LibreLane and
metadata never admit one. This adds no installed waiver feature.
"""

import re


class ContractError(ValueError):
    """Malformed, unsupported or contradictory runtime declaration."""


SUPPORTED_MINORS = ("3.10", "3.11", "3.12", "3.13", "3.14")
REQUIRES_PYTHON = ">=3.10"
_MINOR = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\Z")
_PYTHON = re.compile(r"((?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*))\.(?:0|[1-9][0-9]*)\Z")
_LIBRELANE = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(?:\.(?:dev|a|b|rc)[0-9]+)?\Z")


def _object(value, keys, where):
    if type(value) is not dict or set(value) != set(keys):
        raise ContractError(f"{where}: expected exactly fields {', '.join(keys)}")
    return value


def _string(value, where, pattern=None):
    if type(value) is not str or not value or (pattern and not pattern.fullmatch(value)):
        raise ContractError(f"{where}: invalid string value")
    return value


def _equal(value, expected, where):
    if type(value) is not type(expected) or value != expected:
        raise ContractError(f"{where}: expected {expected!r}")


def policy_from_requested(requested):
    """Parse bundle authority. Absent policy alone selects historical strictness.

    Unrelated requested_tools fields are additive-compatible. Inside schema 1's
    policy, all fields/types/values are checked and unknown fields fail closed.
    Metadata is the bounded adopted >=3.10 / classifiers 3.10..3.14 contract,
    not a general packaging specifier interpreter. LL version comes from bundle.
    """
    if type(requested) is not dict:
        raise ContractError("requested_tools must be an object")
    minor = _string(requested.get("python"), "python", _MINOR)
    ll = _string(requested.get("librelane"), "librelane", _LIBRELANE)
    image = "ghcr.io/librelane/librelane:" + ll
    host = {"python": {"policy": "exact-minor", "version": minor}}
    native = {"policy": "host-runtime"}
    if "runtime_policy" not in requested:
        docker = {"policy": "legacy-exact-minor", "image_ref": image,
                  "python": {"policy": "exact-minor", "version": minor}}
        source = "legacy"
    else:
        p = _object(requested["runtime_policy"],
                    ("schema_version", "host", "implementation"), "runtime_policy")
        _equal(p["schema_version"], 1, "schema_version")
        h = _object(p["host"], ("python",), "host")
        hp = _object(h["python"], ("policy", "version"), "host.python")
        _equal(hp["policy"], "exact-minor", "host.python.policy")
        _equal(hp["version"], minor, "host.python.version (scalar contradiction)")
        impl = _object(p["implementation"], ("native", "dockerized"), "implementation")
        n = _object(impl["native"], ("policy",), "native")
        _equal(n["policy"], "host-runtime", "native.policy")
        d = _object(impl["dockerized"], ("policy", "image_ref", "python"), "dockerized")
        _equal(d["policy"], "official-librelane-image", "dockerized.policy")
        _equal(d["image_ref"], image, "image_ref (LibreLane contradiction)")
        dp = _object(d["python"], ("policy", "requires_python", "supported_minors"),
                     "dockerized.python")
        _equal(dp["policy"], "distribution-supported", "dockerized.python.policy")
        _equal(dp["requires_python"], REQUIRES_PYTHON, "requires_python")
        minors = dp["supported_minors"]
        if (type(minors) is not list or any(type(m) is not str for m in minors)
                or len(minors) != len(SUPPORTED_MINORS)
                or set(minors) != set(SUPPORTED_MINORS)):
            raise ContractError("supported_minors: expected unique adopted minors 3.10..3.14")
        docker = {"policy": d["policy"], "image_ref": image,
                  "python": {"policy": dp["policy"], "requires_python": REQUIRES_PYTHON,
                             "supported_minors": list(SUPPORTED_MINORS)}}
        source = "runtime-policy"
    return {"schema_version": 1, "source": source, "librelane": ll,
            "host": host, "implementation": {"native": native, "dockerized": docker}}


def policy_from_lock(lock):
    """Parse explicit string values from an already-read provisioning lock mapping.

    Never call this to replace a bundle's requested_tools. No file IO or fallback.
    """
    if type(lock) is not dict:
        raise ContractError("lock must be an object")

    def get(key):
        return _string(lock.get(key), "lock." + key)

    _equal(get("runtime_policy_schema_version"), "1", "lock schema_version")
    return policy_from_requested({
        "python": get("python"), "librelane": get("librelane_version"),
        "runtime_policy": {
            "schema_version": 1,
            "host": {"python": {"policy": get("runtime_host_python_policy"),
                                "version": get("runtime_host_python_version")}},
            "implementation": {
                "native": {"policy": get("runtime_native_policy")},
                "dockerized": {
                    "policy": get("runtime_dockerized_policy"),
                    "image_ref": get("runtime_dockerized_image_ref"),
                    "python": {"policy": get("runtime_dockerized_python_policy"),
                               "requires_python": get("runtime_dockerized_requires_python"),
                               "supported_minors": get("runtime_dockerized_supported_minors").split(",")}}}}})


def evaluate(contract, host, container=None, *, native=False, allow_python_mismatch=False):
    """Evaluate a parser-produced contract against normalized observations, purely."""
    if type(native) is not bool or type(allow_python_mismatch) is not bool:
        raise ContractError("evaluation flags must be bool")
    # Reparse to reject malformed caller-created normalized contracts as well.
    _object(contract, ("schema_version", "source", "librelane", "host", "implementation"),
            "contract")
    _equal(contract["schema_version"], 1, "contract.schema_version")
    _object(contract["host"], ("python",), "contract.host")
    _object(contract["host"]["python"], ("policy", "version"), "contract.host.python")
    requested = {"python": contract["host"]["python"]["version"],
                 "librelane": contract["librelane"]}
    if contract["source"] == "runtime-policy":
        requested["runtime_policy"] = {k: contract[k] for k in
                                       ("schema_version", "host", "implementation")}
    elif contract["source"] != "legacy":
        raise ContractError("unknown contract source")
    parsed = policy_from_requested(requested)
    if parsed != contract:
        raise ContractError("non-normalized or contradictory contract")
    result = {"contract": parsed, "native": native, "issues": [], "waivers": [],
              "comparisons": []}

    def compare(role, field, expected, actual, passed, waivable=False):
        waived = not passed and waivable and allow_python_mismatch
        row = {"role": role, "field": field, "expected": expected, "actual": actual,
               "status": "pass" if passed else "waived" if waived else "fail"}
        result["comparisons"].append(row)
        if not passed:
            result["waivers" if waived else "issues"].append(row.copy())

    def python(role, observation, policy):
        actual = observation.get("python_version")
        match = _PYTHON.fullmatch(actual) if type(actual) is str else None
        minor = match.group(1) if match else None
        exact = policy["policy"] == "exact-minor"
        expected = policy["version"] if exact else policy["supported_minors"]
        passed = minor == expected if exact else minor in expected
        compare(role, "python_version", expected, actual, passed,
                bool(match) and exact and parsed["source"] == "legacy")

    if type(host) is not dict or (not native and type(container) is not dict):
        raise ContractError("required observations must be objects")
    python("host", host, parsed["host"]["python"])
    if not native:
        docker = parsed["implementation"]["dockerized"]
        python("container", container, docker["python"])
        compare("container", "librelane_version", parsed["librelane"],
                container.get("librelane_version"),
                type(container.get("librelane_version")) is str
                and container["librelane_version"] == parsed["librelane"])
        if parsed["source"] == "runtime-policy":
            compare("container", "requires_python", REQUIRES_PYTHON,
                    container.get("requires_python"),
                    type(container.get("requires_python")) is str
                    and container["requires_python"] == REQUIRES_PYTHON)
    return result
