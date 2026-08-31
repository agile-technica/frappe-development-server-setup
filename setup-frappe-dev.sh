#!/usr/bin/env bash
set -euo pipefail

readonly DEFAULT_VERSION="16"
readonly RANGE_SIZE=6
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  readonly USE_COLOR=1
else
  readonly USE_COLOR=0
fi

if [[ "$USE_COLOR" == "1" ]]; then
  readonly C_RESET=$'\033[0m'
  readonly C_BLUE=$'\033[1;34m'
  readonly C_CYAN=$'\033[1;36m'
  readonly C_GREEN=$'\033[1;32m'
  readonly C_YELLOW=$'\033[1;33m'
  readonly C_RED=$'\033[1;31m'
  readonly C_MAGENTA=$'\033[1;35m'
  readonly C_WHITE=$'\033[1;37m'
  readonly C_BG_BLUE=$'\033[44m'
else
  readonly C_RESET=""
  readonly C_BLUE=""
  readonly C_CYAN=""
  readonly C_GREEN=""
  readonly C_YELLOW=""
  readonly C_RED=""
  readonly C_MAGENTA=""
  readonly C_WHITE=""
  readonly C_BG_BLUE=""
fi

COMPOSE_CMD=()
PROJECT_NAME=""
FRAPPE_VERSION="$DEFAULT_VERSION"
FRAPPE_PORT_START=""
FRAPPE_PORT_END=""
SOCKETIO_PORT_START=""
SOCKETIO_PORT_END=""
PROJECT_IP_NUMBER=""
SSH_KEY_PATH=""
SSH_PUBLIC_KEY_PATH=""
SSH_KEY_DEST_NAME=""
SSH_KEY_CHOICES=()
SSH_KEY_CHOICE_LABELS=()
SSH_CONFIG_HOST=""
SSH_CONFIG_HOSTNAME=""
SSH_CONFIG_PORT=""
MARIADB_VOLUME_NAME=""
MARIADB_VOLUME_ACTION="not found"

color() {
  local color_code="$1"
  local text="$2"
  printf '%s%s%s' "$color_code" "$text" "$C_RESET"
}

box_line() {
  local text="$1"
  printf '| %-70.70s |\n' "$text"
}

clear_screen() {
  if [[ -t 1 && -z "${NO_CLEAR:-}" ]]; then
    printf '\033[2J\033[H'
  fi
}

banner() {
  local title="$1"
  printf '\n'
  color "$C_BLUE" "+------------------------------------------------------------------------+"
  printf '\n'
  printf '| %s%-70.70s%s |\n' "$C_WHITE" "$title" "$C_RESET"
  color "$C_BLUE" "+------------------------------------------------------------------------+"
  printf '\n'
}

panel() {
  local title="$1"
  shift
  banner "$title"
  local item
  for item in "$@"; do
    box_line "$item"
  done
  color "$C_BLUE" "+------------------------------------------------------------------------+"
  printf '\n'
}

status() {
  color "$C_CYAN" "[*]"
  printf ' %s\n' "$*"
}

ok() {
  color "$C_GREEN" "[OK]"
  printf ' %s\n' "$*"
}

warn() {
  color "$C_YELLOW" "[!]"
  printf ' %s\n' "$*"
}

splash_pause() {
  local delay="$1"
  if [[ -t 1 ]]; then
    sleep "$delay"
  fi
}

splash_sound() {
  local delay

  if [[ ! -t 1 || -n "${NO_SOUND:-}" ]]; then
    return
  fi

  if command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -NonInteractive -Command '
      $path = Join-Path ([System.IO.Path]::GetTempPath()) "frappe-docker-dev-shareware-sting.wav"
      $sampleRate = 44100
      $duration = 1.15
      $samples = [int]($sampleRate * $duration)
      $dataSize = $samples * 2
      $stream = [System.IO.MemoryStream]::new()
      $writer = [System.IO.BinaryWriter]::new($stream)

      $writer.Write([Text.Encoding]::ASCII.GetBytes("RIFF"))
      $writer.Write([int](36 + $dataSize))
      $writer.Write([Text.Encoding]::ASCII.GetBytes("WAVEfmt "))
      $writer.Write([int]16)
      $writer.Write([int16]1)
      $writer.Write([int16]1)
      $writer.Write([int]$sampleRate)
      $writer.Write([int]($sampleRate * 2))
      $writer.Write([int16]2)
      $writer.Write([int16]16)
      $writer.Write([Text.Encoding]::ASCII.GetBytes("data"))
      $writer.Write([int]$dataSize)

      $notes = @(196.00, 246.94, 293.66, 392.00, 493.88, 587.33, 783.99, 987.77)
      $noteLength = 0.115

      for ($i = 0; $i -lt $samples; $i++) {
        $time = $i / $sampleRate
        $noteIndex = [Math]::Min([int]($time / $noteLength), $notes.Length - 1)
        $noteTime = $time - ($noteIndex * $noteLength)
        $frequency = $notes[$noteIndex]
        $attack = [Math]::Min(1.0, $noteTime / 0.012)
        $decay = [Math]::Exp(-7.5 * $noteTime)
        $envelope = $attack * $decay

        $square = if ([Math]::Sin(2 * [Math]::PI * $frequency * $time) -ge 0) { 1.0 } else { -1.0 }
        $octave = if ([Math]::Sin(2 * [Math]::PI * ($frequency * 2) * $time) -ge 0) { 1.0 } else { -1.0 }
        $bassFrequency = 98.0 + (26.0 * [Math]::Sin(2 * [Math]::PI * 2.2 * $time))
        $bass = if ([Math]::Sin(2 * [Math]::PI * $bassFrequency * $time) -ge 0) { 1.0 } else { -1.0 }
        $sparkle = [Math]::Sin(2 * [Math]::PI * (1400 + (320 * $noteIndex)) * $time) * [Math]::Exp(-11.0 * $noteTime)

        $mix = (0.62 * $square * $envelope) + (0.18 * $octave * $envelope) + (0.14 * $bass * [Math]::Sin([Math]::PI * $time / $duration)) + (0.10 * $sparkle)
        $sample = [Math]::Max(-0.95, [Math]::Min(0.95, $mix))
        $writer.Write([int16]($sample * 26000))
      }

      [System.IO.File]::WriteAllBytes($path, $stream.ToArray())
      $player = [System.Media.SoundPlayer]::new($path)
      $player.PlaySync()
      Remove-Item $path -ErrorAction SilentlyContinue
    ' >/dev/null 2>&1 && return
  fi

  for delay in 0.12 0.09 0.06 0.04 0.03; do
    printf '\a'
    sleep "$delay"
  done
}

splash_header() {
  printf '%s%-52s%12s%s\n' "$C_BG_BLUE$C_CYAN" " Frappe Docker Dev Setup - May 2026" "Page 1 of 1" "$C_RESET"
  printf '%s\n' "$(color "$C_MAGENTA" "================================================================")"
}

splash_stars() {
  printf '%s\n' "$(color "$C_CYAN" " *       .          *             .       *              .      ")"
  printf '%s\n' "$(color "$C_BLUE" "     .        *           .             *          .            ")"
  printf '%s\n' "$(color "$C_CYAN" "  .       *        .            *              .          *     ")"
}

splash_credit() {
  if [[ "$USE_COLOR" == "1" ]]; then
    printf '                         %s\n' "$(color "$C_WHITE" "By: Agile Technica")"
    printf '                       %s\n' "$(color "$C_CYAN" "www.agiletechnica.com")"
  else
    printf '                         By: Agile Technica\n'
    printf '                       www.agiletechnica.com\n'
  fi
}

splash_loading_text() {
  if [[ "$USE_COLOR" == "1" ]]; then
    printf '%s\n' "$(color "$C_CYAN" "Keyboard setup wizard loading...")"
    printf '%s\n' "$(color "$C_CYAN" "Press Ctrl-C at any time to cancel.")"
  else
    printf 'Keyboard setup wizard loading...\n'
    printf 'Press Ctrl-C at any time to cancel.\n'
  fi
}

splash_small_logo() {
  printf '\n\n\n'
  printf '                       %s\n' "$(color "$C_RED" "FRAPPE")"
  printf '                    %s\n' "$(color "$C_RED" "DOCKER DEV")"
  printf '\n'
  splash_credit
}

splash_medium_logo() {
  printf '\n\n'
  printf '          %s\n' "$(color "$C_RED" "FFFF  RRRR    AAA   PPPP   PPPP   EEEEE")"
  printf '          %s\n' "$(color "$C_RED" "F     R   R  A   A  P   P  P   P  E    ")"
  printf '          %s\n' "$(color "$C_RED" "FFF   RRRR   AAAAA  PPPP   PPPP   EEEE ")"
  printf '          %s\n' "$(color "$C_RED" "F     R  R   A   A  P      P      E    ")"
  printf '          %s\n' "$(color "$C_RED" "F     R   R  A   A  P      P      EEEEE")"
  printf '\n'
  splash_credit
}

splash_big_logo() {
  printf '\n'
  if [[ "$USE_COLOR" == "1" ]]; then
    printf ' %s\n' "$(color "$C_RED" "                                             ███████")"
    printf ' %s\n' "$(color "$C_RED" "                                   ██████    █      ")"
    printf ' %s\n' "$(color "$C_RED" "                         █████     █    █    █      ")"
    printf ' %s\n' "$(color "$C_RED" "                ████     █   █     ██████    █████  ")"
    printf ' %s\n' "$(color "$C_RED" "       ███     █   █     █████     █         █      ")"
    printf ' %s\n' "$(color "$C_RED" " ████  █  █    ████      █         █         █      ")"
    printf ' %s\n' "$(color "$C_RED" " █     ███     █  █      █         █         ███████")"
    printf ' %s\n' "$(color "$C_RED" " ███   █  █   █    █                              ")"
    printf ' %s\n' "$(color "$C_RED" " █     █   █  █    █                              ")"
    printf '\n'
    printf ' %s\n' "$(color "$C_RED" "████   ███   ████ █   █ █████ ████       ████  █████ █   █")"
    printf ' %s\n' "$(color "$C_RED" "█   █ █   █ █     █  █  █     █   █      █   █ █     █   █")"
    printf ' %s\n' "$(color "$C_RED" "█   █ █   █ █     ███   ████  ████       █   █ ████  █   █")"
    printf ' %s\n' "$(color "$C_RED" "█   █ █   █ █     █  █  █     █  █       █   █ █      █ █ ")"
    printf ' %s\n' "$(color "$C_RED" "████   ███   ████ █   █ █████ █   █      ████  █████   █  ")"
    printf '\n'
    splash_credit
    printf '\n'
    splash_loading_text
  else
    printf ' FFFFF RRRR   AAA  PPPP  PPPP  EEEEE\n'
    printf ' F     R   R A   A P   P P   P E    \n'
    printf ' FFFF  RRRR  AAAAA PPPP  PPPP  EEEE \n'
    printf ' F     R  R  A   A P     P     E    \n'
    printf ' F     R   R A   A P     P     EEEEE\n\n'
    printf ' DDDD   OOO   CCCC K   K EEEEE RRRR       DDDD  EEEEE V   V\n'
    printf ' D   D O   O C     K  K  E     R   R      D   D E     V   V\n'
    printf ' D   D O   O C     KKK   EEEE  RRRR       D   D EEEE  V   V\n'
    printf ' D   D O   O C     K  K  E     R  R       D   D E      V V \n'
    printf ' DDDD   OOO   CCCC K   K EEEEE R   R      DDDD  EEEEE   V  \n\n'
    splash_credit
    printf '\n'
    splash_loading_text
  fi
}

splash_screen() {
  if [[ "$USE_COLOR" == "1" ]]; then
    printf '\033[2J\033[H'
    splash_sound &
    splash_header
    splash_stars
    splash_small_logo
    splash_pause 0.75

    printf '\033[2J\033[H'
    splash_header
    splash_stars
    splash_medium_logo
    splash_pause 0.75

    printf '\033[2J\033[H'
    splash_header
    splash_stars
    splash_big_logo
    splash_pause 1.5
  else
    printf '\n'
    printf '================================================================\n'
    printf ' Frappe Docker Dev Setup\n'
    printf '================================================================\n\n'
    splash_big_logo
  fi
}

fail() {
  local message="$1"
  printf '\n'
  color "$C_RED" "+------------------------------------------------------------------------+"
  printf '\n| %-70s |\n' "SETUP CANNOT CONTINUE"
  color "$C_RED" "+------------------------------------------------------------------------+"
  printf '\n'
  printf '%s\n\n' "$message"
  exit 1
}

prompt_text() {
  local label="$1"
  local default_value="${2:-}"
  local value

  if [[ -n "$default_value" ]]; then
    printf '%s [%s]: ' "$label" "$default_value" >&2
  else
    printf '%s: ' "$label" >&2
  fi

  if ! IFS= read -r value; then
    printf '\n' >&2
    fail "Input ended before setup completed. Run the wizard interactively or provide all required answers."
  fi
  if [[ -z "$value" && -n "$default_value" ]]; then
    value="$default_value"
  fi
  printf '%s' "$value"
}

prompt_yes_no() {
  local label="$1"
  local default_value="${2:-N}"
  local value

  while true; do
    value="$(prompt_text "$label (Y/N)" "$default_value")"
    case "${value^^}" in
      Y|YES) return 0 ;;
      N|NO) return 1 ;;
      *) warn "Please type Y or N." ;;
    esac
  done
}

is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

validate_project_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ || "$1" =~ ^[a-z0-9]$ ]]
}

validate_ssh_host_value() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

expand_path() {
  local path="$1"
  local drive
  local rest

  case "$path" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${path#~/}" ;;
    [A-Za-z]:\\*|[A-Za-z]:/*)
      drive="${path:0:1}"
      rest="${path:2}"
      rest="${rest//\\//}"
      drive="${drive,,}"
      if [[ -d "/mnt/$drive" ]]; then
        printf '/mnt/%s%s' "$drive" "$rest"
      elif [[ -d "/$drive" ]]; then
        printf '/%s%s' "$drive" "$rest"
      else
        printf '%s' "$path"
      fi
      ;;
    *) printf '%s' "$path" ;;
  esac
}

windows_profile_dir() {
  local profile
  local drive
  local rest

  if [[ -n "${USERPROFILE:-}" ]]; then
    profile="$USERPROFILE"
  elif command -v powershell.exe >/dev/null 2>&1; then
    profile="$(powershell.exe -NoProfile -NonInteractive -Command '[Console]::Out.Write($env:USERPROFILE)' </dev/null 2>/dev/null || true)"
    profile="${profile//$'\r'/}"
  else
    return 0
  fi

  [[ -n "$profile" ]] || return 0

  case "$profile" in
    [A-Za-z]:\\*|[A-Za-z]:/*)
      drive="${profile:0:1}"
      rest="${profile:2}"
      rest="${rest//\\//}"
      drive="${drive,,}"
      if [[ -d "/mnt/$drive" ]]; then
        printf '/mnt/%s%s' "$drive" "$rest"
      elif [[ -d "/$drive" ]]; then
        printf '/%s%s' "$drive" "$rest"
      fi
      ;;
    *)
      [[ -d "$profile" ]] && printf '%s' "$profile"
      ;;
  esac
}

discover_ssh_keys() {
  local candidate
  local ssh_dir
  local windows_home
  local source_label
  local seen=":"
  SSH_KEY_CHOICES=()
  SSH_KEY_CHOICE_LABELS=()

  windows_home="$(windows_profile_dir)"

  for ssh_dir in "$HOME/.ssh" "${windows_home:+$windows_home/.ssh}"; do
    [[ -d "$ssh_dir" ]] || continue
    if [[ -n "$windows_home" && "$ssh_dir" == "$windows_home/.ssh" && "$ssh_dir" != "$HOME/.ssh" ]]; then
      source_label="Windows user"
    else
      source_label="WSL/Linux"
    fi

    for candidate in \
      "$ssh_dir/id_ed25519" \
      "$ssh_dir/id_rsa" \
      "$ssh_dir/id_ecdsa" \
      "$ssh_dir/id_dsa" \
      "$ssh_dir"/id_*; do
      [[ -f "$candidate" && -r "$candidate" ]] || continue
      [[ "$candidate" == *.pub || "$candidate" == *-cert.pub ]] && continue
      [[ "$seen" == *":$candidate:"* ]] && continue
      SSH_KEY_CHOICES+=("$candidate")
      SSH_KEY_CHOICE_LABELS+=("$source_label")
      seen="$seen$candidate:"
    done
  done
}

set_ssh_key_path() {
  local key_path="$1"
  key_path="$(expand_path "$key_path")"

  if [[ ! -f "$key_path" || ! -r "$key_path" ]]; then
    warn "SSH key is not readable: $key_path"
    return 1
  fi

  SSH_KEY_PATH="$key_path"
  SSH_KEY_DEST_NAME="$(basename "$key_path")"

  if [[ ! "$SSH_KEY_DEST_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
    warn "SSH key filename can only contain letters, numbers, dots, underscores, and hyphens."
    SSH_KEY_PATH=""
    SSH_KEY_DEST_NAME=""
    SSH_PUBLIC_KEY_PATH=""
    return 1
  fi

  if [[ -f "$key_path.pub" && -r "$key_path.pub" ]]; then
    SSH_PUBLIC_KEY_PATH="$key_path.pub"
  else
    SSH_PUBLIC_KEY_PATH=""
  fi

  return 0
}

detect_compose() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
    return
  fi

  fail "Docker Compose was not found. Install Docker Desktop or Docker Compose, then run this wizard again."
}

compose() {
  "${COMPOSE_CMD[@]}" "$@"
}

docker_available() {
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

port_in_use_by_listener() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -H -ltn "sport = :$port" 2>/dev/null | grep -q .
    return
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -an 2>/dev/null | grep -E "[.:]$port[[:space:]].*LISTEN" >/dev/null
    return
  fi

  return 1
}

port_in_use_by_docker() {
  local port="$1"

  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi

  docker ps --format '{{.Ports}}' 2>/dev/null \
    | grep -E "(^|[ :,])([0-9.]*:|\\[::\\]:)$port->|(^|[ :,])$port->" >/dev/null
}

port_in_use() {
  local port="$1"
  port_in_use_by_listener "$port" || port_in_use_by_docker "$port"
}

range_is_free() {
  local start="$1"
  local end="$2"
  local port

  for ((port = start; port <= end; port++)); do
    if port_in_use "$port"; then
      return 1
    fi
  done

  return 0
}

find_free_range() {
  local preferred="$1"
  local start="$preferred"
  local end=$((start + RANGE_SIZE - 1))

  if range_is_free "$start" "$end"; then
    printf '%s' "$start"
    return
  fi

  for start in $(seq $((preferred + 60)) 10 19990); do
    end=$((start + RANGE_SIZE - 1))
    if range_is_free "$start" "$end"; then
      printf '%s' "$start"
      return
    fi
  done

  fail "Could not find a free $RANGE_SIZE-port range starting near $preferred."
}

subnet_in_use() {
  local number="$1"
  local network_id
  local subnet

  if ! docker_available; then
    return 1
  fi

  while IFS= read -r network_id; do
    [[ -z "$network_id" ]] && continue
    subnet="$(docker network inspect "$network_id" --format '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}' 2>/dev/null || true)"
    if grep -qx "10.88.$number.0/24" <<< "$subnet"; then
      return 0
    fi
  done < <(docker network ls -q 2>/dev/null || true)

  return 1
}

find_free_project_ip_number() {
  local number

  for number in $(seq 0 255); do
    if ! subnet_in_use "$number"; then
      printf '%s' "$number"
      return
    fi
  done

  fail "Could not find an unused 10.88.x.0/24 Docker subnet."
}

scan_network_defaults() {
  FRAPPE_PORT_START="$(find_free_range 8000)"
  FRAPPE_PORT_END=$((FRAPPE_PORT_START + RANGE_SIZE - 1))
  SOCKETIO_PORT_START="$(find_free_range 9000)"
  SOCKETIO_PORT_END=$((SOCKETIO_PORT_START + RANGE_SIZE - 1))
  PROJECT_IP_NUMBER="$(find_free_project_ip_number)"
}

validate_port_range() {
  local start="$1"
  local end="$2"

  is_integer "$start" || return 1
  is_integer "$end" || return 1
  ((start > 0 && start <= 65535)) || return 1
  ((end > 0 && end <= 65535)) || return 1
  ((end - start + 1 == RANGE_SIZE)) || return 1
}

edit_network_defaults() {
  local value

  while true; do
    value="$(prompt_text "Frappe port start" "$FRAPPE_PORT_START")"
    if is_integer "$value" && validate_port_range "$value" "$((value + RANGE_SIZE - 1))"; then
      FRAPPE_PORT_START="$value"
      FRAPPE_PORT_END=$((FRAPPE_PORT_START + RANGE_SIZE - 1))
      break
    fi
    warn "Enter a valid port start. The wizard will reserve $RANGE_SIZE ports."
  done

  while true; do
    value="$(prompt_text "Socket.IO port start" "$SOCKETIO_PORT_START")"
    if is_integer "$value" && validate_port_range "$value" "$((value + RANGE_SIZE - 1))"; then
      SOCKETIO_PORT_START="$value"
      SOCKETIO_PORT_END=$((SOCKETIO_PORT_START + RANGE_SIZE - 1))
      break
    fi
    warn "Enter a valid port start. The wizard will reserve $RANGE_SIZE ports."
  done

  while true; do
    value="$(prompt_text "PROJECT_IP_NUMBER" "$PROJECT_IP_NUMBER")"
    if is_integer "$value" && ((value >= 0 && value <= 255)); then
      PROJECT_IP_NUMBER="$value"
      break
    fi
    warn "Enter a number from 0 to 255."
  done

  if ! range_is_free "$FRAPPE_PORT_START" "$FRAPPE_PORT_END"; then
    warn "The selected Frappe port range appears to be in use."
  fi
  if ! range_is_free "$SOCKETIO_PORT_START" "$SOCKETIO_PORT_END"; then
    warn "The selected Socket.IO port range appears to be in use."
  fi
  if subnet_in_use "$PROJECT_IP_NUMBER"; then
    warn "The selected 10.88.$PROJECT_IP_NUMBER.0/24 subnet appears to be in use."
  fi
}

welcome_screen() {
  clear_screen
  panel "FRAPPE DOCKER DEVELOPMENT SETUP" \
    "Welcome to the keyboard-only setup wizard." \
    "It will create your .env file, workspace folder, and Docker stack." \
    "Prerequisites: Git, Docker, Compose, and registry login if needed." \
    "Default Frappe version: v$DEFAULT_VERSION"
}

project_screen() {
  local value

  clear_screen
  banner "PROJECT SETUP"
  while true; do
    value="$(prompt_text "Project name (lowercase letters, numbers, hyphens)")"
    if validate_project_name "$value"; then
      PROJECT_NAME="$value"
      return
    fi
    warn "Example: erpnext-demo or layer-farm. No spaces, underscores, or uppercase letters."
  done
}

version_screen() {
  local value

  clear_screen
  banner "FRAPPE VERSION"
  printf '  1. v12\n'
  printf '  2. v13\n'
  printf '  3. v14\n'
  printf '  4. v15\n'
  printf '  5. v16 %s\n' "$(color "$C_GREEN" "(default)")"

  while true; do
    value="$(prompt_text "Choose version number or type v12-v16" "v$DEFAULT_VERSION")"
    case "${value,,}" in
      1|12|v12) FRAPPE_VERSION="12"; return ;;
      2|13|v13) FRAPPE_VERSION="13"; return ;;
      3|14|v14) FRAPPE_VERSION="14"; return ;;
      4|15|v15) FRAPPE_VERSION="15"; return ;;
      5|16|v16) FRAPPE_VERSION="16"; return ;;
      *) warn "Choose one of v12, v13, v14, v15, or v16." ;;
    esac
  done
}

network_summary() {
  printf '  Frappe ports    : %s-%s (host and container)\n' "$FRAPPE_PORT_START" "$FRAPPE_PORT_END"
  printf '  Socket.IO ports : %s-%s (host and container)\n' "$SOCKETIO_PORT_START" "$SOCKETIO_PORT_END"
  printf '  Docker subnet   : 10.88.%s.0/24\n' "$PROJECT_IP_NUMBER"
}

network_screen() {
  local value

  clear_screen
  status "Scanning for available ports and Docker subnet..."
  scan_network_defaults

  while true; do
    clear_screen
    banner "NETWORK SETTINGS"
    network_summary
    printf '\n'
    printf '  1. Accept these settings\n'
    printf '  2. Re-scan\n'
    printf '  3. Edit manually\n'
    value="$(prompt_text "Choose" "1")"

    case "$value" in
      1|"") return ;;
      2) status "Re-scanning..."; scan_network_defaults ;;
      3) edit_network_defaults ;;
      *) warn "Choose 1, 2, or 3." ;;
    esac
  done
}

ssh_key_screen() {
  local value
  local custom_path
  local index

  discover_ssh_keys

  while true; do
    clear_screen
    banner "SSH KEY"
    printf '  Optional: copy a host SSH key into the Frappe container.\n'
    printf '  This helps bench get-app clone private Git repositories.\n\n'

    if ((${#SSH_KEY_CHOICES[@]} > 0)); then
      for index in "${!SSH_KEY_CHOICES[@]}"; do
        printf '  %s. [%s] %s\n' "$((index + 1))" "${SSH_KEY_CHOICE_LABELS[$index]}" "${SSH_KEY_CHOICES[$index]}"
      done
      printf '  C. Type a custom key path\n'
      printf '  S. Skip SSH key copy\n\n'
      value="$(prompt_text "Choose SSH key" "1")"

      case "${value,,}" in
        s|skip) SSH_KEY_PATH=""; SSH_PUBLIC_KEY_PATH=""; SSH_KEY_DEST_NAME=""; return ;;
        c|custom)
          custom_path="$(prompt_text "Custom private key path")"
          set_ssh_key_path "$custom_path" && return
          ;;
        *)
          if is_integer "$value" && ((value >= 1 && value <= ${#SSH_KEY_CHOICES[@]})); then
            set_ssh_key_path "${SSH_KEY_CHOICES[$((value - 1))]}" && return
          else
            warn "Choose a listed number, C for custom path, or S to skip."
          fi
          ;;
      esac
    else
      warn "No default SSH keys found in $HOME/.ssh."
      printf '  C. Type a custom key path\n'
      printf '  S. Skip SSH key copy\n\n'
      value="$(prompt_text "Choose" "S")"

      case "${value,,}" in
        s|skip|"") SSH_KEY_PATH=""; SSH_PUBLIC_KEY_PATH=""; SSH_KEY_DEST_NAME=""; return ;;
        c|custom)
          custom_path="$(prompt_text "Custom private key path")"
          set_ssh_key_path "$custom_path" && return
          ;;
        *) warn "Choose C for custom path or S to skip." ;;
      esac
    fi
  done
}

ssh_host_config_screen() {
  local value

  SSH_CONFIG_HOST=""
  SSH_CONFIG_HOSTNAME=""
  SSH_CONFIG_PORT=""

  [[ -n "$SSH_KEY_PATH" ]] || return 0

  clear_screen
  banner "SSH HOST CONFIG"
  printf '  Optional: add an SSH host config inside the Frappe container.\n'
  printf '  Use this for Git hosts that need a custom alias, key, or port.\n\n'

  if ! prompt_yes_no "Add a custom SSH host config?" "N"; then
    return 0
  fi

  while true; do
    value="$(prompt_text "Host alias (example: gitlab.example.com)")"
    if validate_ssh_host_value "$value"; then
      SSH_CONFIG_HOST="$value"
      break
    fi
    warn "Use only letters, numbers, dots, underscores, and hyphens."
  done

  while true; do
    value="$(prompt_text "HostName" "$SSH_CONFIG_HOST")"
    if validate_ssh_host_value "$value"; then
      SSH_CONFIG_HOSTNAME="$value"
      break
    fi
    warn "Use only letters, numbers, dots, underscores, and hyphens."
  done

  while true; do
    value="$(prompt_text "Port" "22")"
    if is_integer "$value" && ((value >= 1 && value <= 65535)); then
      SSH_CONFIG_PORT="$value"
      break
    fi
    warn "Enter a port from 1 to 65535."
  done
}

env_file() {
  printf '%s/.env.%s' "$SCRIPT_DIR" "$PROJECT_NAME"
}

workspace_dir() {
  printf '%s/%s-docker' "$SCRIPT_DIR" "$PROJECT_NAME"
}

fallback_compose_project_name() {
  basename "$SCRIPT_DIR" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/_/g'
}

compose_project_name_from_env() {
  local env_path="$1"
  local project_name

  project_name="$(
    { compose --env-file "$env_path" config --format json 2>/dev/null || true; } \
      | sed -n 's/^[[:space:]]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n 1
  )"

  if [[ -z "$project_name" ]]; then
    project_name="$(
      { compose --env-file "$env_path" config 2>/dev/null || true; } \
        | sed -n 's/^name:[[:space:]]*//p' \
        | head -n 1
    )"
  fi

  if [[ -n "$project_name" ]]; then
    printf '%s' "$project_name"
  else
    fallback_compose_project_name
  fi
}

volume_exists() {
  docker volume inspect "$1" >/dev/null 2>&1
}

mariadb_volume_screen() {
  local tmp_env
  local compose_project

  tmp_env="$(mktemp)"
  write_env_file "$tmp_env"
  compose --env-file "$tmp_env" config >/dev/null
  compose_project="$(compose_project_name_from_env "$tmp_env")"
  rm -f "$tmp_env"

  MARIADB_VOLUME_NAME="${compose_project}_mysql_vol"
  MARIADB_VOLUME_ACTION="not found"

  if ! volume_exists "$MARIADB_VOLUME_NAME"; then
    return 0
  fi

  clear_screen
  banner "MARIADB DATA"
  printf '  Existing MariaDB volume detected:\n\n'
  printf '      %s\n\n' "$MARIADB_VOLUME_NAME"
  printf '  Keeping it preserves local databases and users.\n'
  printf '  Resetting it deletes local MariaDB data for this stack.\n'
  printf '  Reset is useful after a failed or repeated bench initialization.\n\n'

  if prompt_yes_no "Reset this MariaDB volume before starting containers?" "N"; then
    MARIADB_VOLUME_ACTION="reset"
  else
    MARIADB_VOLUME_ACTION="keep"
  fi
}

confirm_overwrite() {
  local env_path="$1"
  local workspace_path="$2"
  local needs_confirmation=0

  if [[ -e "$env_path" ]]; then
    warn "$env_path already exists."
    needs_confirmation=1
  fi

  if [[ -e "$workspace_path" ]]; then
    warn "$workspace_path already exists."
    needs_confirmation=1
  fi

  if [[ "$needs_confirmation" == "1" ]]; then
    prompt_yes_no "Reuse these existing paths and overwrite the env file?" "N" \
      || fail "No files were changed. Choose another project name or remove the existing setup."
  fi
}

confirmation_screen() {
  local env_path
  local workspace_path
  env_path="$(env_file)"
  workspace_path="$(workspace_dir)"

  clear_screen
  banner "CONFIRM SETUP"
  printf '  Project          : %s\n' "$PROJECT_NAME"
  printf '  Site             : %s.localhost\n' "$PROJECT_NAME"
  printf '  Version          : v%s\n' "$FRAPPE_VERSION"
  printf '  Env file         : %s\n' "$env_path"
  printf '  Workspace        : %s\n' "$workspace_path"
  printf '  Containers       : frappe-%s, mariadb-%s, cache-%s, queue-%s, socketio-%s\n' \
    "$PROJECT_NAME" "$PROJECT_NAME" "$PROJECT_NAME" "$PROJECT_NAME" "$PROJECT_NAME"
  if [[ -n "$MARIADB_VOLUME_NAME" ]]; then
    case "$MARIADB_VOLUME_ACTION" in
      reset) printf '  MariaDB volume   : reset %s\n' "$MARIADB_VOLUME_NAME" ;;
      keep) printf '  MariaDB volume   : keep %s\n' "$MARIADB_VOLUME_NAME" ;;
      *) printf '  MariaDB volume   : no existing volume detected\n' ;;
    esac
  fi
  if [[ -n "$SSH_KEY_PATH" ]]; then
    printf '  SSH key          : %s -> /home/frappe/.ssh/%s\n' "$SSH_KEY_PATH" "$SSH_KEY_DEST_NAME"
    if [[ -n "$SSH_PUBLIC_KEY_PATH" ]]; then
      printf '  SSH public key   : %s -> /home/frappe/.ssh/%s.pub\n' "$SSH_PUBLIC_KEY_PATH" "$SSH_KEY_DEST_NAME"
    else
      printf '  SSH public key   : not found, private key only\n'
    fi
    if [[ -n "$SSH_CONFIG_HOST" ]]; then
      printf '  SSH config       : Host %s -> %s:%s\n' "$SSH_CONFIG_HOST" "$SSH_CONFIG_HOSTNAME" "$SSH_CONFIG_PORT"
    else
      printf '  SSH config       : skipped\n'
    fi
  else
    printf '  SSH key          : skipped\n'
  fi
  network_summary
  printf '\n'

  prompt_yes_no "Create this setup and start Docker Compose?" "Y" \
    || fail "Setup cancelled. Nothing was created."
}

write_env_file() {
  local env_path="$1"

  sed \
    -e "s#^PROJECT_NAME=.*#PROJECT_NAME=$PROJECT_NAME#" \
    -e "s#^SITE_NAME=.*#SITE_NAME=$PROJECT_NAME.localhost#" \
    -e "s#^FRAPPE_CONTAINER_NAME=.*#FRAPPE_CONTAINER_NAME=frappe-$PROJECT_NAME#" \
    -e "s#^MARIADB_CONTAINER_NAME=.*#MARIADB_CONTAINER_NAME=mariadb-$PROJECT_NAME#" \
    -e "s#^REDIS_CACHE_CONTAINER_NAME=.*#REDIS_CACHE_CONTAINER_NAME=cache-$PROJECT_NAME#" \
    -e "s#^REDIS_QUEUE_CONTAINER_NAME=.*#REDIS_QUEUE_CONTAINER_NAME=queue-$PROJECT_NAME#" \
    -e "s#^REDIS_SOCKETIO_CONTAINER_NAME=.*#REDIS_SOCKETIO_CONTAINER_NAME=socketio-$PROJECT_NAME#" \
    -e "s#^FRAPPE_PORT_START=.*#FRAPPE_PORT_START=$FRAPPE_PORT_START#" \
    -e "s#^FRAPPE_PORT_END=.*#FRAPPE_PORT_END=$FRAPPE_PORT_END#" \
    -e "s#^SOCKETIO_PORT_START=.*#SOCKETIO_PORT_START=$SOCKETIO_PORT_START#" \
    -e "s#^SOCKETIO_PORT_END=.*#SOCKETIO_PORT_END=$SOCKETIO_PORT_END#" \
    -e "s#^PROJECT_IP_NUMBER=.*#PROJECT_IP_NUMBER=$PROJECT_IP_NUMBER#" \
    "$SCRIPT_DIR/.env" > "$env_path"
}

create_setup() {
  local env_path
  local workspace_path
  env_path="$(env_file)"
  workspace_path="$(workspace_dir)"

  confirm_overwrite "$env_path" "$workspace_path"

  clear_screen
  banner "PROGRESS"
  status "Creating workspace folder..."
  mkdir -p "$workspace_path/mariadb-backup"
  ok "Workspace ready: $workspace_path"

  status "Writing env file..."
  write_env_file "$env_path"
  ok "Env file ready: $env_path"

  status "Validating Docker Compose configuration..."
  compose --env-file "$env_path" config >/dev/null
  ok "Compose configuration is valid."

  if [[ "$MARIADB_VOLUME_ACTION" == "reset" && -n "$MARIADB_VOLUME_NAME" ]]; then
    status "Stopping existing stack before MariaDB reset..."
    compose --env-file "$env_path" down
    status "Removing MariaDB volume: $MARIADB_VOLUME_NAME"
    if ! docker volume rm "$MARIADB_VOLUME_NAME" >/dev/null 2>&1 && volume_exists "$MARIADB_VOLUME_NAME"; then
      fail "Could not remove MariaDB volume $MARIADB_VOLUME_NAME. Stop containers using it, then run the wizard again."
    fi
    ok "MariaDB volume reset complete."
  fi

  status "Starting Docker containers..."
  compose --env-file "$env_path" up -d
  ok "Docker stack is running."
}

copy_ssh_key_to_container() {
  local container_name="frappe-$PROJECT_NAME"
  local private_tmp="/tmp/$SSH_KEY_DEST_NAME"
  local public_tmp="/tmp/$SSH_KEY_DEST_NAME.pub"

  [[ -n "$SSH_KEY_PATH" ]] || return 0

  status "Copying SSH key into $container_name..."
  docker exec "$container_name" bash -lc 'mkdir -p /home/frappe/.ssh && chown frappe:frappe /home/frappe/.ssh && chmod 700 /home/frappe/.ssh'

  docker cp "$SSH_KEY_PATH" "$container_name:$private_tmp"
  docker exec "$container_name" bash -lc "mv '$private_tmp' '/home/frappe/.ssh/$SSH_KEY_DEST_NAME' && chown frappe:frappe '/home/frappe/.ssh/$SSH_KEY_DEST_NAME' && chmod 600 '/home/frappe/.ssh/$SSH_KEY_DEST_NAME'"

  if [[ -n "$SSH_PUBLIC_KEY_PATH" ]]; then
    docker cp "$SSH_PUBLIC_KEY_PATH" "$container_name:$public_tmp"
    docker exec "$container_name" bash -lc "mv '$public_tmp' '/home/frappe/.ssh/$SSH_KEY_DEST_NAME.pub' && chown frappe:frappe '/home/frappe/.ssh/$SSH_KEY_DEST_NAME.pub' && chmod 644 '/home/frappe/.ssh/$SSH_KEY_DEST_NAME.pub'"
  fi

  ok "SSH key copied to /home/frappe/.ssh/$SSH_KEY_DEST_NAME."
}

write_ssh_config_to_container() {
  local container_name="frappe-$PROJECT_NAME"
  local start_marker="# >>> frappe-docker-dev-wizard host $SSH_CONFIG_HOST"
  local end_marker="# <<< frappe-docker-dev-wizard host $SSH_CONFIG_HOST"
  local identity_file="/home/frappe/.ssh/$SSH_KEY_DEST_NAME"

  [[ -n "$SSH_KEY_PATH" && -n "$SSH_CONFIG_HOST" ]] || return 0

  status "Writing SSH host config for $SSH_CONFIG_HOST..."
  docker exec \
    -e "START_MARKER=$start_marker" \
    -e "END_MARKER=$end_marker" \
    -e "HOST_ALIAS=$SSH_CONFIG_HOST" \
    -e "HOST_NAME=$SSH_CONFIG_HOSTNAME" \
    -e "HOST_PORT=$SSH_CONFIG_PORT" \
    -e "IDENTITY_FILE=$identity_file" \
    "$container_name" bash -lc '
      set -e
      config=/home/frappe/.ssh/config
      tmp=/tmp/frappe-docker-dev-ssh-config
      mkdir -p /home/frappe/.ssh
      touch "$config"
      awk -v start="$START_MARKER" -v end="$END_MARKER" "
        \$0 == start { skip = 1; next }
        \$0 == end { skip = 0; next }
        skip != 1 { print }
      " "$config" > "$tmp"
      {
        printf "%s\n" "$START_MARKER"
        printf "Host %s\n" "$HOST_ALIAS"
        printf " HostName %s\n" "$HOST_NAME"
        printf " IdentityFile %s\n" "$IDENTITY_FILE"
        printf " IdentitiesOnly yes\n"
        printf " Port %s\n" "$HOST_PORT"
        printf "%s\n" "$END_MARKER"
      } >> "$tmp"
      mv "$tmp" "$config"
      chown frappe:frappe /home/frappe/.ssh "$config"
      chmod 700 /home/frappe/.ssh
      chmod 600 "$config"
    '
  ok "SSH config updated for Host $SSH_CONFIG_HOST."
}

final_screen() {
  clear_screen
  banner "READY"
  printf '  You are about to enter the Frappe container.\n'
  printf '  Inside the container, run:\n\n'
  printf '      %s\n\n' "$(color "$C_GREEN" "source frappe-bench-startup-v$FRAPPE_VERSION.sh")"
  printf '  After bench initialization, start Frappe from /workspace/frappe-bench as usual.\n\n'

  if [[ -t 0 ]]; then
    prompt_text "Press ENTER to enter frappe-$PROJECT_NAME" "" >/dev/null
  fi
}

enter_container() {
  docker exec -e "TERM=xterm-256color" -it "frappe-$PROJECT_NAME" bash
}

main() {
  cd "$SCRIPT_DIR"

  splash_screen
  welcome_screen
  detect_compose
  ok "Using Compose command: ${COMPOSE_CMD[*]}"

  if ! docker_available; then
    fail "Docker is installed, but the Docker daemon is not available. Start Docker, then run this wizard again."
  fi

  project_screen
  version_screen
  [[ -f "$SCRIPT_DIR/frappe-startup-scripts/frappe-bench-startup-v$FRAPPE_VERSION.sh" ]] \
    || fail "Missing startup script: frappe-startup-scripts/frappe-bench-startup-v$FRAPPE_VERSION.sh"
  network_screen
  ssh_key_screen
  ssh_host_config_screen
  mariadb_volume_screen
  confirmation_screen
  create_setup
  copy_ssh_key_to_container
  write_ssh_config_to_container
  final_screen
  enter_container
}

main "$@"
