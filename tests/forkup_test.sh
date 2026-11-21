#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORKUP="$ROOT/bin/forkup"
GIT_BIN="$(dirname "$(command -v git)")"
EMPTY_CONFIG="$(mktemp)"
export GIT_CONFIG_GLOBAL="$EMPTY_CONFIG"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test
export GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test
export GIT_COMMITTER_EMAIL=test@example.com

tmps=()
cleanup() {
  local d
  if [[ "${#tmps[@]}" -gt 0 ]]; then
    for d in "${tmps[@]}"; do
      rm -rf "$d"
    done
  fi
  rm -f "$EMPTY_CONFIG"
}
trap cleanup EXIT

newtmp() {
  local d
  d="$(mktemp -d)"
  tmps[${#tmps[@]}]="$d"
  printf '%s\n' "$d"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

expect_fail() {
  local expected="$1"
  shift
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -ne 1 ]]; then
    fail "expected exit 1, got ${status}: ${output}"
  fi
  if [[ "$output" != *"$expected"* ]]; then
    fail "expected [${expected}] in [${output}]"
  fi
}

test_rejects_arguments() {
  local base
  base="$(newtmp)"
  (
    cd "$base"
    expect_fail "no arguments" "$FORKUP" extra
  )
  pass "no arguments"
}

test_rejects_non_repo() {
  local base
  base="$(newtmp)"
  (
    cd "$base"
    expect_fail "not a git repository" "$FORKUP"
  )
  pass "not a git repository"
}

test_rejects_untracked() {
  local base head
  base="$(newtmp)"
  git init -b main "$base/repo" >/dev/null
  echo tracked > "$base/repo/file"
  git -C "$base/repo" add file
  git -C "$base/repo" commit -m base >/dev/null
  echo junk > "$base/repo/untracked"
  head="$(git -C "$base/repo" rev-parse HEAD)"
  (
    cd "$base/repo"
    expect_fail "working tree is dirty" "$FORKUP"
  )
  [[ "$(git -C "$base/repo" rev-parse HEAD)" == "$head" ]] || fail "HEAD moved"
  [[ -f "$base/repo/untracked" ]] || fail "untracked file removed"
  pass "dirty worktree"
}

prepare_conflict_repo() {
  local base="$1"
  git init -b main "$base/repo" >/dev/null
  echo a > "$base/repo/file"
  git -C "$base/repo" add file
  git -C "$base/repo" commit -m a >/dev/null
  git -C "$base/repo" checkout -b other >/dev/null
  echo other > "$base/repo/file"
  git -C "$base/repo" commit -am other >/dev/null
  git -C "$base/repo" checkout main >/dev/null
  echo main > "$base/repo/file"
  git -C "$base/repo" commit -am main >/dev/null
}

test_rejects_rebase() {
  local base head
  base="$(newtmp)"
  prepare_conflict_repo "$base"
  git -C "$base/repo" checkout other >/dev/null
  set +e
  git -C "$base/repo" rebase main >/dev/null 2>&1
  set -e
  head="$(git -C "$base/repo" rev-parse HEAD)"
  (
    cd "$base/repo"
    expect_fail "rebase in progress" "$FORKUP"
  )
  [[ "$(git -C "$base/repo" rev-parse HEAD)" == "$head" ]] || fail "HEAD moved during rebase"
  pass "rebase in progress"
}

test_rejects_merge() {
  local base head
  base="$(newtmp)"
  prepare_conflict_repo "$base"
  set +e
  git -C "$base/repo" merge other >/dev/null 2>&1
  set -e
  head="$(git -C "$base/repo" rev-parse HEAD)"
  (
    cd "$base/repo"
    expect_fail "merge in progress" "$FORKUP"
  )
  [[ "$(git -C "$base/repo" rev-parse HEAD)" == "$head" ]] || fail "HEAD moved during merge"
  pass "merge in progress"
}

test_rejects_cherry_pick() {
  local base head
  base="$(newtmp)"
  prepare_conflict_repo "$base"
  set +e
  git -C "$base/repo" cherry-pick other >/dev/null 2>&1
  set -e
  head="$(git -C "$base/repo" rev-parse HEAD)"
  (
    cd "$base/repo"
    expect_fail "cherry-pick in progress" "$FORKUP"
  )
  [[ "$(git -C "$base/repo" rev-parse HEAD)" == "$head" ]] || fail "HEAD moved during cherry-pick"
  pass "cherry-pick in progress"
}

test_rejects_arguments
test_rejects_non_repo
test_rejects_untracked
test_rejects_rebase
test_rejects_merge
test_rejects_cherry_pick
echo "all passed"
