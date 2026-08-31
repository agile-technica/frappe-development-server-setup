#!/usr/bin/env bash

# Shared helpers for the versioned startup scripts. These scripts are intended
# to be sourced so that NVM, pyenv, and bench remain available afterwards.

frappe_startup_fail() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

frappe_validate_ports() {
  local name value start end

  for name in FRAPPE_PORT_START FRAPPE_PORT_END SOCKETIO_PORT_START SOCKETIO_PORT_END; do
    value="${!name:-}"
    [[ "$value" =~ ^[0-9]+$ ]] || {
      frappe_startup_fail "$name must be set to a numeric port by Docker Compose."
      return 1
    }
    ((value >= 1 && value <= 65535)) || {
      frappe_startup_fail "$name must be between 1 and 65535."
      return 1
    }
  done

  start="$FRAPPE_PORT_START"
  end="$FRAPPE_PORT_END"
  ((end - start + 1 == 6)) || {
    frappe_startup_fail "Frappe must be assigned a six-port range."
    return 1
  }

  start="$SOCKETIO_PORT_START"
  end="$SOCKETIO_PORT_END"
  ((end - start + 1 == 6)) || {
    frappe_startup_fail "Socket.IO must be assigned a six-port range."
    return 1
  }
}

frappe_load_nvm() {
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    frappe_startup_fail "NVM is unavailable at $NVM_DIR/nvm.sh."
    return 1
  fi
  # shellcheck source=/dev/null
  . "$NVM_DIR/nvm.sh"
}

frappe_resolve_node() {
  NODE_BIN="$(command -v node || true)"
  if [[ -z "$NODE_BIN" ]]; then
    frappe_startup_fail "Node is unavailable after loading NVM."
    return 1
  fi
  export NODE_BIN
}

frappe_python_major_minor() {
  "$1" -c 'import sys; print("%s.%s" % sys.version_info[:2])'
}

frappe_rebuild_bench_env_if_needed() {
  local python_bin="$1"
  local bench_dir="${FRAPPE_BENCH_DIR:-/workspace/frappe-bench}"
  local expected_version current_version backup_env

  [[ -d "$bench_dir" ]] || return 0
  [[ -d "$bench_dir/apps/frappe" && -d "$bench_dir/sites" ]] || {
    frappe_startup_fail "$bench_dir exists but is not a valid Bench; refusing to overwrite it."
    return 1
  }

  expected_version="$(frappe_python_major_minor "$python_bin")" || return 1
  current_version="$(frappe_python_major_minor "$bench_dir/env/bin/python" 2>/dev/null || true)"
  [[ "$current_version" == "$expected_version" ]] && return 0

  printf 'Rebuilding incompatible Bench Python environment (%s -> %s).\n' \
    "${current_version:-unavailable}" "$expected_version"
  backup_env="$bench_dir/env.runtime-backup.$$"
  if [[ -e "$bench_dir/env" ]]; then
    mv "$bench_dir/env" "$backup_env"
  fi

  if (cd "$bench_dir" && bench setup env --python "$python_bin"); then
    if [[ -e "$backup_env" ]]; then
      rm -rf -- "$backup_env"
    fi
  else
    rm -rf -- "$bench_dir/env"
    if [[ -e "$backup_env" ]]; then
      mv "$backup_env" "$bench_dir/env"
    fi
    frappe_startup_fail "Bench environment rebuild failed; the previous environment was restored."
    return 1
  fi
}

frappe_prepare_bench() {
  local frappe_version="$1"
  local python_bin="$2"
  local bench_dir="${FRAPPE_BENCH_DIR:-/workspace/frappe-bench}"
  local workspace_dir
  workspace_dir="$(dirname "$bench_dir")"

  frappe_rebuild_bench_env_if_needed "$python_bin" || return 1
  if [[ ! -d "$bench_dir" ]]; then
    (cd "$workspace_dir" && bench init --skip-redis-config-generation \
      --python "$python_bin" --frappe-branch "version-$frappe_version" "$(basename "$bench_dir")" --verbose) || return 1
  fi

  cd "$bench_dir" || return 1
  bench setup requirements
}

frappe_write_procfile_ports() {
  local bench_dir="${FRAPPE_BENCH_DIR:-/workspace/frappe-bench}"
  local procfile="$bench_dir/Procfile"
  local tmp="$bench_dir/Procfile.port-update.$$"

  if [[ ! -f "$procfile" ]]; then
    (cd "$bench_dir" && bench setup procfile --skip-redis) || return 1
  fi

  awk -v web_port="$FRAPPE_PORT_START" -v node_bin="$NODE_BIN" '
    /^web:/ { print "web: bench serve --port " web_port; web_seen=1; next }
    /^socketio:/ { print "socketio: " node_bin " apps/frappe/socketio.js"; socket_seen=1; next }
    { print }
    END {
      if (!web_seen) print "web: bench serve --port " web_port
      if (!socket_seen) print "socketio: " node_bin " apps/frappe/socketio.js"
    }
  ' "$procfile" > "$tmp" && mv "$tmp" "$procfile"
}

frappe_configure_bench() {
  local bench_dir="${FRAPPE_BENCH_DIR:-/workspace/frappe-bench}"
  cd "$bench_dir" || return 1
  bench set-mariadb-host "$MARIADB_CONTAINER_NAME" || return 1
  bench set-redis-cache-host "$REDIS_CACHE_CONTAINER_NAME:6379" || return 1
  bench set-redis-queue-host "$REDIS_QUEUE_CONTAINER_NAME:6379" || return 1
  bench set-redis-socketio-host "$REDIS_SOCKETIO_CONTAINER_NAME:6379" || return 1
  bench set-config -g webserver_port "$FRAPPE_PORT_START" || return 1
  bench set-config -g socketio_port "$SOCKETIO_PORT_START" || return 1
  frappe_write_procfile_ports || return 1

  git -C apps/frappe config core.autocrlf input || return 1
  git -C apps/frappe config core.filemode false || return 1

  if [[ ! -f "sites/$SITE_NAME/site_config.json" ]]; then
    bench new-site "$SITE_NAME" --mariadb-root-password root --admin-password administrator \
      --no-mariadb-socket --db-name erpnext --verbose || return 1
  fi
  bench --site "$SITE_NAME" set-config developer_mode 1 || return 1
  bench --site "$SITE_NAME" clear-cache || return 1
  bench use "$SITE_NAME"
}
