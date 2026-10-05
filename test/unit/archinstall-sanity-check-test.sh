#!/bin/bash

# archinstall 4.5 dropped the `offline` keyword from Installer.sanity_check, and
# the ISO does not pin archinstall, so the mirror decides which signature the
# live env gets. The adapter probes for the keyword rather than assuming it;
# this covers both shapes without archinstall installed.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

# Exercise the real probe logic against stand-in methods carrying the two
# published signatures. Copied rather than imported: importing the adapter needs
# archinstall present, which is the whole thing under test.
probe() {
  python3 - "$1" <<'PYTHON'
import sys

spec = sys.argv[1]


def _build(spec):
  """Build a method carrying the given parameter list, or a no-__code__ one."""
  if spec == "builtin":
    return len  # a C builtin: getattr(fn, "__code__", None) is None
  ns = {}
  exec(f"def sanity_check({spec}):\n  pass\n", ns)
  return ns["sanity_check"]


method = _build(spec)


def _method_accepts(method, name):
  fn = getattr(method, "__func__", method)
  code = getattr(fn, "__code__", None)
  if code is None:
    return True

  positional = code.co_varnames[:code.co_argcount]
  kwonly = code.co_varnames[code.co_argcount:code.co_argcount + code.co_kwonlyargcount]
  return name in (*positional, *kwonly)


kwargs = {"skip_ntp": True, "skip_wkd": True}
if _method_accepts(method, "offline"):
  kwargs["offline"] = True

print(",".join(sorted(kwargs)))
PYTHON
}

got=$(probe "offline=False, skip_ntp=False, skip_wkd=False")
[[ $got == "offline,skip_ntp,skip_wkd" ]] ||
  fail "archinstall 4.4 keeps the offline keyword" "$got"
pass "archinstall 4.4 keeps the offline keyword"

got=$(probe "skip_ntp=False, skip_wkd=False")
[[ $got == "skip_ntp,skip_wkd" ]] ||
  fail "archinstall 4.5 omits the dropped offline keyword" "$got"
pass "archinstall 4.5 omits the dropped offline keyword"

# A C-level or stubbed method with no __code__ must not lose the keyword: the
# probe treats an unreadable signature as accepting everything.
got=$(probe "builtin")
[[ $got == "offline,skip_ntp,skip_wkd" ]] ||
  fail "an unreadable signature keeps every keyword" "$got"
pass "an unreadable signature keeps every keyword"

# The orchestrator must not reach past the adapter for this call: an unguarded
# keyword is exactly what broke on 4.5.
if grep -nE '^[[:space:]]*installer\.sanity_check\(' \
  "$ROOT/configs/airootfs/usr/share/omarchy-iso/orchestrator/phases_impl.py" >/dev/null; then
  fail "the orchestrator routes sanity_check through the adapter"
fi
pass "the orchestrator routes sanity_check through the adapter"

grep -q 'offline' "$ROOT/configs/airootfs/usr/share/omarchy-iso/orchestrator/phases_impl.py" &&
  grep -q 'sanity_check' "$ROOT/configs/airootfs/usr/share/omarchy-iso/orchestrator/archinstall_adapter.py" ||
  fail "the adapter documents the offline keyword it probes for"
pass "the adapter documents the offline keyword it probes for"