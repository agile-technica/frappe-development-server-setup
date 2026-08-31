#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../frappe-startup-scripts/frappe-bench-startup-common.sh
. "$ROOT_DIR/frappe-startup-scripts/frappe-bench-startup-common.sh"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_contains() {
  grep -Fqx "$2" "$1" || fail_test "$1 does not contain: $2"
}

FRAPPE_PORT_START=8060
FRAPPE_PORT_END=8065
SOCKETIO_PORT_START=9060
SOCKETIO_PORT_END=9065
frappe_validate_ports

FRAPPE_PORT_END=8064
if frappe_validate_ports 2>/dev/null; then
  fail_test "five-port Frappe range was accepted"
fi
FRAPPE_PORT_END=8065

if PATH="$TEST_DIR/empty-path" frappe_resolve_node 2>/dev/null; then
  fail_test "missing Node was accepted"
fi

FRAPPE_BENCH_DIR="$TEST_DIR/procfile-bench"
mkdir -p "$FRAPPE_BENCH_DIR"
printf '%s\n' \
  'web: bench serve --port 8000' \
  'socketio: /old/node apps/frappe/socketio.js' \
  'worker_default: bench worker --queue default' > "$FRAPPE_BENCH_DIR/Procfile"
NODE_BIN=/home/frappe/.nvm/versions/node/v22.0.0/bin/node
frappe_write_procfile_ports
assert_file_contains "$FRAPPE_BENCH_DIR/Procfile" 'web: bench serve --port 8060'
assert_file_contains "$FRAPPE_BENCH_DIR/Procfile" "socketio: $NODE_BIN apps/frappe/socketio.js"
assert_file_contains "$FRAPPE_BENCH_DIR/Procfile" 'worker_default: bench worker --queue default'

mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/bench" <<'EOF'
#!/usr/bin/env bash
set -e
[[ "$1 $2 $3" == "setup env --python" ]]
[[ "${MOCK_BENCH_FAIL:-0}" != "1" ]]
mkdir -p env/bin
ln -s "$4" env/bin/python
EOF
chmod +x "$TEST_DIR/bin/bench"

FRAPPE_BENCH_DIR="$TEST_DIR/resume-bench"
mkdir -p "$FRAPPE_BENCH_DIR/apps/frappe" "$FRAPPE_BENCH_DIR/sites" "$FRAPPE_BENCH_DIR/env/bin"
printf 'preserve apps\n' > "$FRAPPE_BENCH_DIR/apps/custom-marker"
printf 'preserve sites\n' > "$FRAPPE_BENCH_DIR/sites/site-marker"
printf '#!/usr/bin/env bash\nprintf "0.0\\n"\n' > "$FRAPPE_BENCH_DIR/env/bin/python"
chmod +x "$FRAPPE_BENCH_DIR/env/bin/python"
PATH="$TEST_DIR/bin:$PATH" frappe_rebuild_bench_env_if_needed "$(command -v python3)"
[[ -f "$FRAPPE_BENCH_DIR/apps/custom-marker" ]] || fail_test "apps were not preserved"
[[ -f "$FRAPPE_BENCH_DIR/sites/site-marker" ]] || fail_test "sites were not preserved"
[[ "$(frappe_python_major_minor "$FRAPPE_BENCH_DIR/env/bin/python")" == "$(frappe_python_major_minor "$(command -v python3)")" ]] \
  || fail_test "Python environment was not rebuilt"

printf 'compatible environment\n' > "$FRAPPE_BENCH_DIR/env/compatible-marker"
PATH="$TEST_DIR/bin:$PATH" frappe_rebuild_bench_env_if_needed "$(command -v python3)"
[[ -f "$FRAPPE_BENCH_DIR/env/compatible-marker" ]] || fail_test "compatible environment was replaced"

rm "$FRAPPE_BENCH_DIR/env/bin/python"
ln -s "$TEST_DIR/missing-python" "$FRAPPE_BENCH_DIR/env/bin/python"
PATH="$TEST_DIR/bin:$PATH" frappe_rebuild_bench_env_if_needed "$(command -v python3)"
[[ -x "$FRAPPE_BENCH_DIR/env/bin/python" ]] || fail_test "broken Python environment was not rebuilt"

rm "$FRAPPE_BENCH_DIR/env/bin/python"
ln -s "$TEST_DIR/still-missing-python" "$FRAPPE_BENCH_DIR/env/bin/python"
if MOCK_BENCH_FAIL=1 PATH="$TEST_DIR/bin:$PATH" \
  frappe_rebuild_bench_env_if_needed "$(command -v python3)" 2>/dev/null; then
  fail_test "failed environment rebuild was reported as successful"
fi
[[ -L "$FRAPPE_BENCH_DIR/env/bin/python" ]] || fail_test "failed rebuild did not restore the previous environment"

printf 'All startup helper tests passed.\n'
