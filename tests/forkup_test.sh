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

test_fetch_failure_keeps_upstream() {
  local base bin head
  base="$(newtmp)"
  bin="$base/bin"
  make_pair "$base"
  install_fake_gh "$bin" "$base/missing.git" main true local/upstream
  head="$(git -C "$base/work" rev-parse HEAD)"
  with_git_path "$bin" "$base/work" expect_fail "failed to fetch upstream" "$FORKUP"
  [[ "$(git -C "$base/work" remote get-url upstream)" == "$base/missing.git" ]] || fail "upstream remote dropped after fetch failure"
  [[ "$(git -C "$base/work" rev-parse HEAD)" == "$head" ]] || fail "HEAD moved after fetch failure"
  [[ "$(git -C "$base/work" branch --show-current)" == "main" ]] || fail "branch changed after fetch failure"
  pass "fetch failure keeps upstream"
}

test_fast_forward() {
  local base bin upstream_head
  base="$(newtmp)"
  bin="$base/bin"
  make_pair "$base"
  echo two >> "$base/seed/file"
  git -C "$base/seed" commit -am two >/dev/null
  git -C "$base/seed" push upstream main >/dev/null
  install_fake_gh "$bin" "$base/upstream.git" main true local/upstream
  with_git_path "$bin" "$base/work" "$FORKUP"
  upstream_head="$(git -C "$base/upstream.git" rev-parse main)"
  [[ "$(git -C "$base/work" rev-parse HEAD)" == "$upstream_head" ]] || fail "work was not fast-forwarded"
  [[ "$(git -C "$base/origin.git" rev-parse main)" == "$upstream_head" ]] || fail "origin was not fast-forwarded"
  [[ "$(git -C "$base/work" branch --show-current)" == "main" ]] || fail "not on main"
  pass "fast-forward"
}

test_rebase_unique_commits() {
  local base bin upstream_head
  base="$(newtmp)"
  bin="$base/bin"
  make_pair "$base"
  echo up > "$base/seed/up"
  git -C "$base/seed" add up
  git -C "$base/seed" commit -m upstream-change >/dev/null
  git -C "$base/seed" push upstream main >/dev/null
  echo mine > "$base/work/mine"
  git -C "$base/work" add mine
  git -C "$base/work" commit -m fork-change >/dev/null
  install_fake_gh "$bin" "$base/upstream.git" main true local/upstream
  with_git_path "$bin" "$base/work" "$FORKUP"
  upstream_head="$(git -C "$base/upstream.git" rev-parse main)"
  [[ "$(git -C "$base/work" log -1 --format=%s)" == "fork-change" ]] || fail "fork commit not on top"
  [[ "$(git -C "$base/work" log -1 --format=%P)" == "$upstream_head" ]] || fail "fork commit was not rebased onto upstream"
  [[ -f "$base/work/up" && -f "$base/work/mine" ]] || fail "rebase dropped file contents"
  [[ "$(git -C "$base/origin.git" rev-parse main)" == "$(git -C "$base/work" rev-parse HEAD)" ]] || fail "origin does not match rebased work"
  [[ "$(git -C "$base/origin.git" log -1 --format=%s)" == "fork-change" ]] || fail "origin missing rebased commit"
  pass "rebase unique commits"
}

test_switches_to_default_branch() {
  local base bin feature upstream_head
  base="$(newtmp)"
  bin="$base/bin"
  make_pair "$base"
  echo two >> "$base/seed/file"
  git -C "$base/seed" commit -am two >/dev/null
  git -C "$base/seed" push upstream main >/dev/null
  git -C "$base/work" checkout -b feature >/dev/null
  echo f > "$base/work/feature-file"
  git -C "$base/work" add feature-file
  git -C "$base/work" commit -m feature-change >/dev/null
  feature="$(git -C "$base/work" rev-parse HEAD)"
  install_fake_gh "$bin" "$base/upstream.git" main true local/upstream
  with_git_path "$bin" "$base/work" "$FORKUP"
  upstream_head="$(git -C "$base/upstream.git" rev-parse main)"
  [[ "$(git -C "$base/work" branch --show-current)" == "main" ]] || fail "did not stay on default branch"
  [[ "$(git -C "$base/work" rev-parse feature)" == "$feature" ]] || fail "feature branch moved"
  [[ "$(git -C "$base/work" rev-parse HEAD)" == "$upstream_head" ]] || fail "default branch was not updated"
  [[ ! -f "$base/work/feature-file" ]] || fail "feature file checked out on default branch"
  pass "switches to default branch"
}

test_rebase_conflict_does_not_push() {
  local base bin origin_head git_dir
  base="$(newtmp)"
  bin="$base/bin"
  make_pair "$base"
  echo upstream > "$base/seed/file"
  git -C "$base/seed" commit -am upstream-change >/dev/null
  git -C "$base/seed" push upstream main >/dev/null
  echo fork > "$base/work/file"
  git -C "$base/work" commit -am fork-change >/dev/null
  origin_head="$(git -C "$base/origin.git" rev-parse main)"
  install_fake_gh "$bin" "$base/upstream.git" main true local/upstream
  with_git_path "$bin" "$base/work" expect_fail "rebase conflict" "$FORKUP"
  status="$(git -C "$base/work" status)"
  [[ "$status" == *"rebasing branch 'main'"* ]] || fail "conflict did not happen on default branch"
  git_dir="$(git -C "$base/work" rev-parse --absolute-git-dir)"
  if [[ ! -d "$git_dir/rebase-merge" && ! -d "$git_dir/rebase-apply" ]]; then
    fail "rebase was not left in progress"
  fi
  [[ "$(git -C "$base/origin.git" rev-parse main)" == "$origin_head" ]] || fail "origin changed despite rebase conflict"
  pass "rebase conflict does not push"
}

test_force_with_lease_refusal() {
  local base bin wrap side upstream_head
  base="$(newtmp)"
  bin="$base/bin"
  wrap="$base/wrap"
  make_pair "$base"
  echo two >> "$base/seed/file"
  git -C "$base/seed" commit -am two >/dev/null
  git -C "$base/seed" push upstream main >/dev/null
  git clone "$base/origin.git" "$base/side" >/dev/null 2>&1
  mkdir -p "$wrap"
  cat > "$wrap/git" <<EOF
#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == "push" && "\$*" == *"--force-with-lease"* && ! -f "$base/leased" ]]; then
  touch "$base/leased"
  "$GIT_BIN/git" -C "$base/side" commit --allow-empty -m "someone else" >/dev/null
  "$GIT_BIN/git" -C "$base/side" push origin main >/dev/null
fi
exec "$GIT_BIN/git" "\$@"
EOF
  chmod +x "$wrap/git"
  install_fake_gh "$bin" "$base/upstream.git" main true local/upstream
  (
    cd "$base/work"
    export PATH="$wrap:$bin:$GIT_BIN:/usr/bin:/bin"
    expect_fail "force-with-lease refused" "$FORKUP"
  )
  upstream_head="$(git -C "$base/upstream.git" rev-parse main)"
  [[ "$(git -C "$base/work" rev-parse HEAD)" == "$upstream_head" ]] || fail "local branch was not rebased before the refused push"
  [[ "$(git -C "$base/origin.git" log -1 --format=%s)" == "someone else" ]] || fail "origin is not the competing commit"
  [[ "$(git -C "$base/origin.git" rev-parse main)" != "$(git -C "$base/work" rev-parse HEAD)" ]] || fail "refused push still updated origin to local HEAD"
  pass "force-with-lease refusal"
}

test_pushes_missing_origin_branch() {
  local base bin
  base="$(newtmp)"
  bin="$base/bin"
  git init --bare -b main "$base/upstream.git" >/dev/null
  git init --bare -b main "$base/origin.git" >/dev/null
  git init -b main "$base/seed" >/dev/null
  echo base > "$base/seed/file"
  git -C "$base/seed" add file
  git -C "$base/seed" commit -m base >/dev/null
  git -C "$base/seed" remote add origin "$base/upstream.git"
  git -C "$base/seed" push origin main >/dev/null
  git clone "$base/upstream.git" "$base/work" >/dev/null 2>&1
  git -C "$base/work" remote rename origin upstream
  git -C "$base/work" remote add origin "$base/origin.git"
  install_fake_gh "$bin" "$base/wrong.git" main true local/upstream
  with_git_path "$bin" "$base/work" "$FORKUP"
  [[ "$(git -C "$base/work" remote get-url upstream)" == "$base/upstream.git" ]] || fail "existing upstream replaced"
  [[ "$(git -C "$base/origin.git" rev-parse main)" == "$(git -C "$base/work" rev-parse HEAD)" ]] || fail "missing origin branch was not pushed"
  pass "pushes missing origin branch"
}

test_origin_fetch_failure_keeps_branch() {
  local base bin head
  base="$(newtmp)"
  bin="$base/bin"
  make_pair "$base"
  git -C "$base/work" remote set-url origin "$base/missing-origin.git"
  install_fake_gh "$bin" "$base/upstream.git" main true local/upstream
  head="$(git -C "$base/work" rev-parse HEAD)"
  with_git_path "$bin" "$base/work" expect_fail "failed to fetch origin" "$FORKUP"
  [[ "$(git -C "$base/work" remote get-url upstream)" == "$base/upstream.git" ]] || fail "upstream missing after origin fetch failure"
  [[ "$(git -C "$base/work" rev-parse HEAD)" == "$head" ]] || fail "HEAD moved after origin fetch failure"
  [[ "$(git -C "$base/work" branch --show-current)" == "main" ]] || fail "branch changed after origin fetch failure"
  pass "origin fetch failure"
}

test_creates_missing_local_default_branch() {
  local base bin feature upstream_head
  base="$(newtmp)"
  bin="$base/bin"
  make_pair "$base"
  echo two >> "$base/seed/file"
  git -C "$base/seed" commit -am two >/dev/null
  git -C "$base/seed" push upstream main >/dev/null
  git -C "$base/work" checkout -b feature >/dev/null
  echo f > "$base/work/feature-file"
  git -C "$base/work" add feature-file
  git -C "$base/work" commit -m feature-change >/dev/null
  feature="$(git -C "$base/work" rev-parse HEAD)"
  git -C "$base/work" branch -D main >/dev/null
  install_fake_gh "$bin" "$base/upstream.git" main true local/upstream
  with_git_path "$bin" "$base/work" "$FORKUP"
  upstream_head="$(git -C "$base/upstream.git" rev-parse main)"
  [[ "$(git -C "$base/work" branch --show-current)" == "main" ]] || fail "missing main was not created"
  [[ "$(git -C "$base/work" rev-parse HEAD)" == "$upstream_head" ]] || fail "created main was not rebased onto upstream"
  [[ "$(git -C "$base/work" rev-parse feature)" == "$feature" ]] || fail "feature moved while creating main"
  pass "creates missing local default branch"
}

test_uses_parent_default_branch_name() {
  local base bin upstream_head
  base="$(newtmp)"
  bin="$base/bin"
  git init --bare -b trunk "$base/upstream.git" >/dev/null
  git init --bare -b trunk "$base/origin.git" >/dev/null
  git init -b trunk "$base/seed" >/dev/null
  echo base > "$base/seed/file"
  git -C "$base/seed" add file
  git -C "$base/seed" commit -m base >/dev/null
  git -C "$base/seed" remote add upstream "$base/upstream.git"
  git -C "$base/seed" remote add origin "$base/origin.git"
  git -C "$base/seed" push upstream trunk >/dev/null
  git -C "$base/seed" push origin trunk >/dev/null
  git clone "$base/origin.git" "$base/work" >/dev/null 2>&1
  echo two >> "$base/seed/file"
  git -C "$base/seed" commit -am two >/dev/null
  git -C "$base/seed" push upstream trunk >/dev/null
  install_fake_gh "$bin" "$base/upstream.git" trunk true local/upstream
  with_git_path "$bin" "$base/work" "$FORKUP"
  upstream_head="$(git -C "$base/upstream.git" rev-parse trunk)"
  [[ "$(git -C "$base/work" branch --show-current)" == "trunk" ]] || fail "did not switch to parent default branch"
  [[ "$(git -C "$base/work" rev-parse HEAD)" == "$upstream_head" ]] || fail "trunk was not fast-forwarded"
  [[ "$(git -C "$base/origin.git" rev-parse trunk)" == "$upstream_head" ]] || fail "origin trunk was not updated"
  pass "uses parent default branch name"
}

test_tracks_upstream_when_origin_lacks_branch() {
  local base bin upstream_head
  base="$(newtmp)"
  bin="$base/bin"
  git init --bare -b main "$base/upstream.git" >/dev/null
  git init --bare -b main "$base/origin.git" >/dev/null
  git init -b main "$base/seed" >/dev/null
  echo base > "$base/seed/file"
  git -C "$base/seed" add file
  git -C "$base/seed" commit -m base >/dev/null
  git -C "$base/seed" remote add origin "$base/upstream.git"
  git -C "$base/seed" push origin main >/dev/null
  git clone "$base/upstream.git" "$base/work" >/dev/null 2>&1
  echo two >> "$base/seed/file"
  git -C "$base/seed" commit -am two >/dev/null
  git -C "$base/seed" push origin main >/dev/null
  git -C "$base/work" remote rename origin upstream
  git -C "$base/work" remote add origin "$base/origin.git"
  git -C "$base/work" checkout -b side >/dev/null
  git -C "$base/work" branch -D main >/dev/null
  install_fake_gh "$bin" "$base/wrong.git" main true local/upstream
  with_git_path "$bin" "$base/work" "$FORKUP"
  upstream_head="$(git -C "$base/upstream.git" rev-parse main)"
  [[ "$(git -C "$base/work" branch --show-current)" == "main" ]] || fail "did not create main from upstream"
  [[ "$(git -C "$base/work" rev-parse HEAD)" == "$upstream_head" ]] || fail "main does not match upstream"
  [[ "$(git -C "$base/origin.git" rev-parse main)" == "$upstream_head" ]] || fail "origin main was not pushed"
  pass "tracks upstream when origin lacks the branch"
}

test_fetch_failure_keeps_upstream
test_fast_forward
test_rebase_unique_commits
test_switches_to_default_branch
test_rebase_conflict_does_not_push
test_force_with_lease_refusal
test_pushes_missing_origin_branch
test_origin_fetch_failure_keeps_branch
test_creates_missing_local_default_branch
test_uses_parent_default_branch_name
test_tracks_upstream_when_origin_lacks_branch

test_zshrc_path() {
  local zshrc="$ROOT/.zshrc" out
  if ! grep -F 'export PATH="$HOME/dotfiles/bin:$PATH"' "$zshrc" >/dev/null; then
    fail "dotfiles bin is not prepended in .zshrc"
  fi
  if grep -F 'bin/forkup' "$ROOT/setup.sh" >/dev/null; then
    fail "setup.sh mentions forkup"
  fi
  out="$(zsh -f -c '
    PATH=/usr/bin:/bin
    HOME=/tmp/forkup-home
    if [[ ":$PATH:" != *":$HOME/dotfiles/bin:"* ]]; then
      export PATH="$HOME/dotfiles/bin:$PATH"
    fi
    if [[ ":$PATH:" != *":$HOME/dotfiles/bin:"* ]]; then
      export PATH="$HOME/dotfiles/bin:$PATH"
    fi
    print -r -- "$PATH"
  ')"
  [[ "$out" == "/tmp/forkup-home/dotfiles/bin:/usr/bin:/bin" ]] || fail "path prepend is not idempotent: $out"
  pass "zshrc path"
}

test_zshrc_path
echo "all passed"
