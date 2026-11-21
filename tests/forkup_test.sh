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

install_fake_gh() {
  local bin="$1"
  local upstream_url="$2"
  local branch="$3"
  local is_fork="$4"
  local nwo="$5"
  mkdir -p "$bin"
  cat > "$bin/gh" <<EOF
#!/bin/bash
set -euo pipefail
joined="\$*"
if [[ "\$joined" == *"isFork,parent"* ]]; then
  if [[ "$is_fork" == "true" ]]; then
    printf 'true\t%s\n' "$nwo"
  else
    printf 'false\t/\n'
  fi
  exit 0
fi
if [[ "\$joined" == *"--json url"* ]]; then
  printf '%s\n' "$upstream_url"
  exit 0
fi
if [[ "\$joined" == *"defaultBranchRef"* ]]; then
  printf '%s\n' "$branch"
  exit 0
fi
echo "unexpected gh invocation: \$joined" >&2
exit 1
EOF
  chmod +x "$bin/gh"
}

with_git_path() {
  local bin="$1"
  shift
  (
    cd "$1"
    shift
    export PATH="$bin:$GIT_BIN:/usr/bin:/bin"
    "$@"
  )
}

make_pair() {
  local base="$1"
  git init --bare -b main "$base/upstream.git" >/dev/null
  git init --bare -b main "$base/origin.git" >/dev/null
  git init -b main "$base/seed" >/dev/null
  echo base > "$base/seed/file"
  git -C "$base/seed" add file
  git -C "$base/seed" commit -m base >/dev/null
  git -C "$base/seed" remote add upstream "$base/upstream.git"
  git -C "$base/seed" remote add origin "$base/origin.git"
  git -C "$base/seed" push upstream main >/dev/null
  git -C "$base/seed" push origin main >/dev/null
  git clone "$base/origin.git" "$base/work" >/dev/null 2>&1
}

test_rejects_non_fork() {
  local base bin
  base="$(newtmp)"
  bin="$base/bin"
  make_pair "$base"
  install_fake_gh "$bin" "/wrong" main false local/upstream
  with_git_path "$bin" "$base/work" expect_fail "not a fork" "$FORKUP"
  if git -C "$base/work" remote get-url upstream >/dev/null 2>&1; then
    fail "upstream remote was added for a non-fork"
  fi
  pass "not a fork"
}

test_rejects_missing_gh() {
  local base bin
  base="$(newtmp)"
  bin="$base/bin"
  mkdir -p "$bin"
  ln -s "$(command -v git)" "$bin/git"
  make_pair "$base"
  (
    cd "$base/work"
    export PATH="$bin:/usr/bin:/bin"
    expect_fail "gh is required" "$FORKUP"
  )
  pass "gh is required"
}

test_rejects_gh_failure() {
  local base bin
  base="$(newtmp)"
  bin="$base/bin"
  mkdir -p "$bin"
  printf '%s\n' '#!/bin/bash' 'exit 1' > "$bin/gh"
  chmod +x "$bin/gh"
  make_pair "$base"
  with_git_path "$bin" "$base/work" expect_fail "gh repo view failed" "$FORKUP"
  if git -C "$base/work" remote get-url upstream >/dev/null 2>&1; then
    fail "upstream remote was added after gh failure"
  fi
  pass "gh failure"
}

test_adds_upstream() {
  local base bin
  base="$(newtmp)"
  bin="$base/bin"
  make_pair "$base"
  install_fake_gh "$bin" "$base/upstream.git" main true local/upstream
  with_git_path "$bin" "$base/work" "$FORKUP"
  [[ "$(git -C "$base/work" remote get-url upstream)" == "$base/upstream.git" ]] || fail "upstream url mismatch"
  pass "adds upstream"
}

test_keeps_existing_upstream() {
  local base bin
  base="$(newtmp)"
  bin="$base/bin"
  make_pair "$base"
  git -C "$base/work" remote add upstream "$base/upstream.git"
  install_fake_gh "$bin" "$base/wrong.git" main true local/upstream
  with_git_path "$bin" "$base/work" "$FORKUP"
  [[ "$(git -C "$base/work" remote get-url upstream)" == "$base/upstream.git" ]] || fail "upstream url was rewritten"
  pass "keeps existing upstream"
}

test_requires_gh_when_upstream_exists() {
  local base bin url
  base="$(newtmp)"
  bin="$base/bin"
  mkdir -p "$bin"
  ln -s "$(command -v git)" "$bin/git"
  make_pair "$base"
  git -C "$base/work" remote add upstream "$base/upstream.git"
  url="$(git -C "$base/work" remote get-url upstream)"
  (
    cd "$base/work"
    export PATH="$bin:/usr/bin:/bin"
    expect_fail "gh is required" "$FORKUP"
  )
  [[ "$(git -C "$base/work" remote get-url upstream)" == "$url" ]] || fail "upstream url changed without gh"
  [[ "$(git -C "$base/work" branch --show-current)" == "main" ]] || fail "branch changed without gh"
  pass "gh required when upstream exists"
}

test_existing_upstream_not_a_fork() {
  local base bin head
  base="$(newtmp)"
  bin="$base/bin"
  make_pair "$base"
  git -C "$base/work" remote add upstream "$base/upstream.git"
  install_fake_gh "$bin" "/wrong" main false local/upstream
  head="$(git -C "$base/work" rev-parse HEAD)"
  with_git_path "$bin" "$base/work" expect_fail "not a fork" "$FORKUP"
  [[ "$(git -C "$base/work" remote get-url upstream)" == "$base/upstream.git" ]] || fail "upstream url changed"
  [[ "$(git -C "$base/work" rev-parse HEAD)" == "$head" ]] || fail "HEAD moved"
  [[ "$(git -C "$base/work" branch --show-current)" == "main" ]] || fail "branch changed"
  pass "existing upstream still requires a fork"
}

test_rejects_non_fork
test_rejects_missing_gh
test_rejects_gh_failure
test_adds_upstream
test_keeps_existing_upstream
test_requires_gh_when_upstream_exists
test_existing_upstream_not_a_fork
echo "all passed"
