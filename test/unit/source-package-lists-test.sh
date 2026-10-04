#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT/builder/source-package-lists.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

unbloarchy_source="$work/unbloarchy"
mkdir -p "$unbloarchy_source/install"
touch "$unbloarchy_source/install/unbloarchy-base.packages"
touch "$unbloarchy_source/install/unbloarchy-other.packages"

select_source_package_lists "$unbloarchy_source" ||
  fail "Unbloarchy package lists are selected"
[[ ${base_pkg_lists[0]} == "$unbloarchy_source/install/unbloarchy-base.packages" ]] ||
  fail "Unbloarchy base package list is selected"
[[ ${base_pkg_lists[1]} == "$unbloarchy_source/install/unbloarchy-other.packages" ]] ||
  fail "Unbloarchy other package list is selected"
pass "Unbloarchy package lists are selected"

upstream_source="$work/omarchy"
mkdir -p "$upstream_source/install"
touch "$upstream_source/install/omarchy-base.packages"
touch "$upstream_source/install/omarchy-other.packages"

select_source_package_lists "$upstream_source" ||
  fail "upstream package lists remain supported"
[[ ${base_pkg_lists[0]} == "$upstream_source/install/omarchy-base.packages" ]] ||
  fail "upstream base package list is selected"
[[ ${base_pkg_lists[1]} == "$upstream_source/install/omarchy-other.packages" ]] ||
  fail "upstream other package list is selected"
pass "upstream package lists remain supported"

both_source="$work/both"
mkdir -p "$both_source/install"
touch "$both_source/install/unbloarchy-base.packages"
touch "$both_source/install/unbloarchy-other.packages"
touch "$both_source/install/omarchy-base.packages"
touch "$both_source/install/omarchy-other.packages"

select_source_package_lists "$both_source" ||
  fail "source containing both naming schemes resolves"
[[ ${base_pkg_lists[0]} == "$both_source/install/unbloarchy-base.packages" ]] ||
  fail "Unbloarchy package lists take precedence"
pass "Unbloarchy package lists take precedence"

incomplete_source="$work/incomplete"
mkdir -p "$incomplete_source/install"
touch "$incomplete_source/install/unbloarchy-base.packages"
if select_source_package_lists "$incomplete_source"; then
  fail "incomplete package-list pairs are rejected"
fi
pass "incomplete package-list pairs are rejected"
