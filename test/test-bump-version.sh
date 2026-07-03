#!/usr/bin/env bash
# Harness for bump-version.sh. Spins up throwaway cargo packages and
# workspaces in a temp dir, runs each bump action and checks the resulting
# version, the exit code and the next= line in GITHUB_OUTPUT. No GitHub
# needed. Requires cargo, cargo-edit (cargo set-version) and jq.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUMP="$SCRIPT_DIR/../bump-version.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
check() { # description expected actual
  if [ "$2" = "$3" ]; then
    echo "  OK   $1"
    pass=$((pass + 1))
  else
    echo "  FAIL $1: expected '$2', got '$3'"
    fail=$((fail + 1))
  fi
}

RC_FILE="$TMP/rc"
run_bump() { # action -> prints next; exit code into $RC_FILE
  # rc goes to a file, not a variable: run_bump is called from $(...), and a
  # subshell assignment would not reach the parent.
  local out log
  out="$(mktemp)"
  log="$(mktemp)"
  set +e
  GITHUB_OUTPUT="$out" "$BUMP" "$1" > "$log" 2>&1
  echo $? > "$RC_FILE"
  set -e
  sed -n 's/^next=//p' "$out" | tail -n1
  rm -f "$out" "$log"
}

manifest_ver() { # manifest-path
  cargo read-manifest --manifest-path "$1" | jq -r .version
}

new_package() { # dir version
  rm -rf "$1"
  mkdir -p "$1/src"
  cd "$1"
  printf '[package]\nname = "harness"\nversion = "%s"\nedition = "2021"\n' "$2" > Cargo.toml
  echo 'fn main() {}' > src/main.rs
  cargo generate-lockfile > /dev/null 2>&1
}

new_workspace() { # dir version - root package plus one member
  rm -rf "$1"
  mkdir -p "$1/src" "$1/member/src"
  cd "$1"
  printf '[package]\nname = "harness"\nversion = "%s"\nedition = "2021"\n\n[workspace]\nmembers = ["member"]\n' "$2" > Cargo.toml
  echo 'fn main() {}' > src/main.rs
  printf '[package]\nname = "member"\nversion = "%s"\nedition = "2021"\n' "$2" > member/Cargo.toml
  echo '' > member/src/lib.rs
  cargo generate-lockfile > /dev/null 2>&1
}

echo "scenario: plain bumps"
new_package "$TMP/patch" 0.1.0
check "patch" 0.1.1 "$(run_bump patch)"
check "patch rc" 0 "$(cat "$RC_FILE")"
new_package "$TMP/minor" 0.1.5
check "minor" 0.2.0 "$(run_bump minor)"
new_package "$TMP/major" 0.2.3
check "major" 1.0.0 "$(run_bump major)"

echo "scenario: beta starts a patch pre-release"
new_package "$TMP/beta-start" 0.1.0
check "beta from release" 0.1.1-beta.1 "$(run_bump beta)"

echo "scenario: beta increments an active pre-release"
new_package "$TMP/beta-next" 0.1.0
run_bump beta > /dev/null
check "beta from beta" 0.1.1-beta.2 "$(run_bump beta)"

echo "scenario: beta-minor / beta-major set the target base"
new_package "$TMP/beta-minor" 0.1.5
check "beta-minor" 0.2.0-beta.1 "$(run_bump beta-minor)"
new_package "$TMP/beta-major" 0.1.5
check "beta-major" 1.0.0-beta.1 "$(run_bump beta-major)"

echo "scenario: beta-minor from an active pre-release"
new_package "$TMP/beta-minor-active" 0.2.0-beta.3
check "beta-minor from beta" 0.3.0-beta.1 "$(run_bump beta-minor)"

echo "scenario: finalize drops the pre-release"
new_package "$TMP/finalize" 1.2.0-beta.2
check "finalize" 1.2.0 "$(run_bump finalize)"

echo "scenario: finalize with no pre-release fails loud"
new_package "$TMP/finalize-noop" 1.2.0
v="$(run_bump finalize)"
check "no next output" "" "$v"
check "non-zero exit" nonzero "$([ "$(cat "$RC_FILE")" -ne 0 ] && echo nonzero || echo zero)"

echo "scenario: unknown action fails loud"
new_package "$TMP/unknown" 0.1.0
v="$(run_bump frobnicate)"
check "no next output" "" "$v"
check "non-zero exit" nonzero "$([ "$(cat "$RC_FILE")" -ne 0 ] && echo nonzero || echo zero)"
check "version untouched" 0.1.0 "$(manifest_ver Cargo.toml)"

echo "scenario: workspace bumps every member"
new_workspace "$TMP/ws" 0.1.0
check "root" 0.1.1 "$(run_bump patch)"
check "member" 0.1.1 "$(manifest_ver member/Cargo.toml)"
check "lock consistent" ok "$(cargo metadata --format-version 1 --locked > /dev/null 2>&1 && echo ok || echo fail)"

echo
echo "total: pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
