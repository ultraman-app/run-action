#!/usr/bin/env bash
# `ultraman run` with the action's inputs; its exit code is the step's (0 passed, 1 failed, 2 couldn't run).
# bash 3.2 (macOS runners): no empty "${array[@]}" under set -u, hence the ${x[@]+...} forms.
set -u

fail() { echo "::error::$1"; echo "exit-code=2" >> "${GITHUB_OUTPUT:-/dev/null}"; exit 2; }
trim() { local text="$1"; text="${text#"${text%%[![:space:]]*}"}"; printf '%s' "${text%"${text##*[![:space:]]}"}"; }

case $INPUT_JUNIT in *$'\n'* | *$'\r'*) fail "junit: a path can't hold a line break" ;; esac

# The home prepare.mjs trusted the project in (set here, not through GITHUB_ENV, so later steps keep their own).
export ULTRAMAN_HOME="$RUNNER_TEMP/ultraman-home"

# --local: never hand the run to a serve a checked-out ultraman/.serve points at.
args=(run --local)
if [ -n "$(trim "$INPUT_LOAD")" ]; then
  args+=(--load "$(trim "$INPUT_LOAD")")
else
  while IFS= read -r line; do
    line=$(trim "$line")
    [ -n "$line" ] && args+=("$line")
  done <<< "$INPUT_PIPELINES"
fi
[ -n "$INPUT_ENV" ] && args+=(--env "$INPUT_ENV")
args+=(--junit "$INPUT_JUNIT")
[ "$INPUT_YES" = true ] && args+=(--yes)
# Extra flags split on spaces (read -a does no globbing): a quoted value with a space can't go through `args`.
read -r -a extra <<< "$INPUT_ARGS"
args+=(${extra[@]+"${extra[@]}"})

case $INPUT_JUNIT in /* | [A-Za-z]:[\\/]*) junit=$INPUT_JUNIT ;; *) junit="$(pwd)/$INPUT_JUNIT" ;; esac
if [ "${RUNNER_OS:-}" = Windows ]; then
  # Git Bash can't hand arguments to ultraman.cmd intact: call its Node and script the way the .cmd does, with MSYS's
  # path conversion off (it would rewrite arguments starting with /).
  launcher=$(command -v ultraman.cmd) || fail "the ultraman command wasn't installed"
  cli=$(dirname "$launcher")
  export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'
  run_cli() { "$cli/node.exe" --experimental-strip-types --no-warnings=ExperimentalWarning "$cli/bin/ultraman.js" "$@"; }
  junit=$(cygpath -w "$junit")
else
  command -v ultraman > /dev/null || fail "the ultraman command wasn't installed"
  run_cli() { ultraman "$@"; }
fi

run_cli "${args[@]}"
code=$?
{
  echo "exit-code=$code"
  echo "junit=$junit"
} >> "${GITHUB_OUTPUT:-/dev/null}"
exit "$code"
