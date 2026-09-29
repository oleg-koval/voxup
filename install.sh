#!/usr/bin/env bash
#
# voxup - one-command sane setup for the `vox` TTS CLI on Apple Silicon macOS.
#
# Configures a neural English voice (Qwen backend), optionally installs a fun
# game sound pack, and optionally sets up a persistent background daemon.
#
# Compatible with bash 3.2 (macOS default /bin/bash). No mapfile, no
# associative arrays, no `case (pattern)` leading-paren syntax.

LOG_FILE="/tmp/voxup-install.log"
PACK_MANIFEST_COMMIT="cb09d49adad4e79618e3b599a35974d542ed75a7"
PACK_BASE_URL="https://raw.githubusercontent.com/PeonPing/peon-ping/${PACK_MANIFEST_COMMIT}/packs"
VOX_BIN="/opt/homebrew/bin/vox"
HOOK_URL="https://raw.githubusercontent.com/oleg-koval/voxup/main/hooks/vox-speak-stop.sh"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOK_PATH="$CLAUDE_DIR/hooks/vox-speak-stop.sh"

VOICE="Ethan"
PACK=""
DAEMON=0
CLAUDE=0
CLONE_NAME=""
CLONE_AUDIO=""
CLONE_TEXT=""
DOCTOR=0
SHOW_HELP=0

# Real Qwen3-TTS-12Hz-0.6B-Base speakers. vox's own --help advertises
# Chelsie/Aidan/Luna/Ryan, but only these three actually exist; anything else
# silently falls back to female Chelsie inside vox. We validate against this
# list instead of trusting vox's advertised names.
VALID_VOICES="Chelsie Ethan Vivian"

# Pack names known to exist at the pinned pre-move commit.
VALID_PACKS="peon peon_fr peon_pl peasant peasant_fr sc_kerrigan sc_battlecruiser ra2_soviet_engineer"

usage() {
  cat <<'EOF'
voxup - configure the vox TTS CLI on Apple Silicon macOS

Usage:
  install.sh [options]

Options:
  --voice <name>   Voice to configure (default: Ethan)
                   Valid: Chelsie (f), Ethan (m), Vivian (f)
  --pack <name>    Install and set a sound pack (default: none)
                   Valid: peon, peon_fr, peon_pl, peasant, peasant_fr,
                          sc_kerrigan, sc_battlecruiser, ra2_soviet_engineer
  --daemon         Install and load a persistent vox background daemon
                   WARNING: known upstream bug: daemon ignores voice setting
                   (always speaks as Chelsie) and is slower than direct
                   generation (8-9s vs ~6s). Not recommended.
  --clone <name>   Register a voice clone and use it as the voice
                   (requires --clone-audio; qwen backend)
  --clone-audio <wav>  Reference audio for --clone (a few clean seconds)
  --clone-text <text>  Transcript of the reference audio (improves quality)
  --claude         Wire vox into Claude Code: register the vox MCP server
                   and add a Stop hook that speaks the first line of every
                   final reply (see hooks/vox-speak-stop.sh)
  --doctor         Re-check prerequisites and print diagnostics, no changes
  --help           Show this help and exit

Log file: /tmp/voxup-install.log
EOF
  return 0
}

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
  return 0
}

step_ok() {
  echo "OK  $1"
  return 0
}

step_fail() {
  echo "X   $1"
  return 0
}

contains_word() {
  # $1 = space-separated list, $2 = candidate word
  local list="$1"
  local candidate="$2"
  local item
  for item in $list; do
    if [ "$item" = "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --voice)
        VOICE="$2"
        shift 2
        ;;
      --pack)
        PACK="$2"
        shift 2
        ;;
      --daemon)
        DAEMON=1
        shift
        ;;
      --clone)
        CLONE_NAME="$2"
        shift 2
        ;;
      --clone-audio)
        CLONE_AUDIO="$2"
        shift 2
        ;;
      --clone-text)
        CLONE_TEXT="$2"
        shift 2
        ;;
      --claude)
        CLAUDE=1
        shift
        ;;
      --doctor)
        DOCTOR=1
        shift
        ;;
      --help|-h)
        SHOW_HELP=1
        shift
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
  return 0
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

check_macos_arm() {
  local os
  local arch
  os="$(uname -s 2>>"$LOG_FILE")"
  arch="$(uname -m 2>>"$LOG_FILE")"
  log "uname -s: $os, uname -m: $arch"
  if [ "$os" != "Darwin" ]; then
    return 1
  fi
  if [ "$arch" != "arm64" ]; then
    return 1
  fi
  return 0
}

check_homebrew() {
  if command -v brew >/dev/null 2>>"$LOG_FILE"; then
    return 0
  fi
  return 1
}

check_vox_installed() {
  if [ -x "$VOX_BIN" ]; then
    return 0
  fi
  if command -v vox >/dev/null 2>>"$LOG_FILE"; then
    return 0
  fi
  return 1
}

resolve_vox_bin() {
  if [ -x "$VOX_BIN" ]; then
    echo "$VOX_BIN"
    return 0
  fi
  command -v vox 2>>"$LOG_FILE"
  return 0
}

step_preflight() {
  if ! check_macos_arm; then
    step_fail "Preflight: requires macOS on Apple Silicon (arm64)"
    log "Preflight failed: not macOS/arm64"
    exit 1
  fi

  if ! check_homebrew; then
    step_fail "Preflight: homebrew not found"
    log "Preflight failed: brew missing"
    exit 1
  fi

  if check_vox_installed; then
    step_ok "Preflight (macOS arm64, homebrew, vox present)"
    return 0
  fi

  log "vox not found, attempting: brew install vox"
  if brew install vox >>"$LOG_FILE" 2>&1; then
    if check_vox_installed; then
      step_ok "Preflight (macOS arm64, homebrew, vox installed via brew)"
      return 0
    fi
  fi

  step_fail "Preflight: vox missing and 'brew install vox' failed"
  echo "    Install vox manually, then re-run: brew install vox" >&2
  echo "    See $LOG_FILE for details." >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Step 2: neural TTS backend (mlx-audio)
# ---------------------------------------------------------------------------

step_mlx_audio() {
  if python3 -c "import mlx_audio" >>"$LOG_FILE" 2>&1; then
    step_ok "mlx-audio backend (already installed)"
    return 0
  fi

  log "Installing mlx-audio via pip --user --break-system-packages"
  if python3 -m pip install --user --break-system-packages mlx-audio >>"$LOG_FILE" 2>&1; then
    if python3 -c "import mlx_audio" >>"$LOG_FILE" 2>&1; then
      step_ok "mlx-audio backend installed"
      return 0
    fi
  fi

  step_fail "mlx-audio backend install failed"
  echo "    See $LOG_FILE for details." >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Step 3: voice configuration
# ---------------------------------------------------------------------------

validate_voice() {
  local voice="$1"
  if contains_word "$VALID_VOICES" "$voice"; then
    return 0
  fi
  return 1
}

step_configure_voice() {
  local vox
  vox="$(resolve_vox_bin)"

  if [ -n "$CLONE_NAME" ]; then
    VOICE="$CLONE_NAME"
  elif ! validate_voice "$VOICE"; then
    step_fail "Voice '$VOICE' is not a real Qwen3-TTS-12Hz-0.6B-Base speaker"
    echo "    vox advertises Chelsie/Aidan/Luna/Ryan for the qwen backend, but" >&2
    echo "    only Chelsie (f), Ethan (m), Vivian (f) actually exist. Any other" >&2
    echo "    name silently falls back to female Chelsie inside vox." >&2
    echo "    Pass --voice Chelsie, --voice Ethan, or --voice Vivian." >&2
    exit 1
  fi

  if ! "$vox" config set backend qwen >>"$LOG_FILE" 2>&1; then
    step_fail "vox config set backend qwen failed"
    exit 1
  fi
  if ! "$vox" config set lang en >>"$LOG_FILE" 2>&1; then
    step_fail "vox config set lang en failed"
    exit 1
  fi
  if ! "$vox" config set voice "$VOICE" >>"$LOG_FILE" 2>&1; then
    step_fail "vox config set voice $VOICE failed"
    exit 1
  fi

  step_ok "Voice configured (backend=qwen lang=en voice=$VOICE)"
  return 0
}

# ---------------------------------------------------------------------------
# Step 4: sound pack (optional, works around vox's broken pack installer)
# ---------------------------------------------------------------------------

validate_pack() {
  local pack="$1"
  if contains_word "$VALID_PACKS" "$pack"; then
    return 0
  fi
  return 1
}

step_install_pack() {
  local pack="$1"
  local vox
  local pack_dir
  local sounds_dir
  local manifest_path

  if [ -z "$pack" ]; then
    return 0
  fi

  if ! validate_pack "$pack"; then
    step_fail "Pack '$pack' is not known at pinned commit $PACK_MANIFEST_COMMIT"
    echo "    Valid packs: $VALID_PACKS" >&2
    exit 1
  fi

  vox="$(resolve_vox_bin)"
  pack_dir="$HOME/Library/Application Support/vox/packs/$pack"
  sounds_dir="$pack_dir/sounds"
  manifest_path="$pack_dir/manifest.json"

  mkdir -p "$sounds_dir" 2>>"$LOG_FILE"

  log "Downloading manifest for pack '$pack' from pinned commit"
  if ! curl -fsSL "$PACK_BASE_URL/$pack/manifest.json" -o "$manifest_path" >>"$LOG_FILE" 2>&1; then
    step_fail "Pack '$pack': failed to download manifest.json"
    exit 1
  fi

  local files
  files="$(python3 -c "
import json, sys
with open('$manifest_path') as f:
    data = json.load(f)

names = []

def walk(node):
    if isinstance(node, dict):
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for item in node:
            walk(item)
    elif isinstance(node, str):
        if node.endswith(('.wav', '.mp3', '.ogg', '.flac')):
            names.append(node)

walk(data)
for name in sorted(set(names)):
    print(name)
" 2>>"$LOG_FILE")"

  if [ -z "$files" ]; then
    step_fail "Pack '$pack': manifest parsed but no audio files listed"
    exit 1
  fi

  local file
  local fail_count=0
  echo "$files" | while IFS= read -r file; do
    if [ -z "$file" ]; then
      continue
    fi
    if ! curl -fsSL "$PACK_BASE_URL/$pack/sounds/$file" -o "$sounds_dir/$file" >>"$LOG_FILE" 2>&1; then
      log "Failed to download sound file: $file"
      fail_count=$((fail_count + 1))
    fi
  done

  if [ ! -f "$manifest_path" ]; then
    step_fail "Pack '$pack': manifest missing after download"
    exit 1
  fi

  if ! "$vox" pack set "$pack" >>"$LOG_FILE" 2>&1; then
    step_fail "vox pack set $pack failed"
    exit 1
  fi

  step_ok "Sound pack '$pack' installed (worked around broken vox pack installer)"
  return 0
}

# ---------------------------------------------------------------------------
# Step 5: persistent daemon (optional)
# ---------------------------------------------------------------------------

step_install_daemon() {
  local plist_label
  local plist_path
  local uid

  plist_label="com.$(id -un).vox-daemon"
  plist_path="$HOME/Library/LaunchAgents/${plist_label}.plist"
  uid="$(id -u)"

  mkdir -p "$HOME/Library/LaunchAgents" 2>>"$LOG_FILE"

  cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${plist_label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${VOX_BIN}</string>
    <string>daemon</string>
    <string>_run</string>
    <string>--idle-timeout</string>
    <string>0</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/vox-daemon.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/vox-daemon.log</string>
</dict>
</plist>
EOF

  if [ ! -f "$plist_path" ]; then
    step_fail "Daemon: failed to write $plist_path"
    exit 1
  fi

  # bootout first if already loaded; ignore errors (not loaded is fine)
  launchctl bootout "gui/${uid}/${plist_label}" >>"$LOG_FILE" 2>&1

  if ! launchctl bootstrap "gui/${uid}" "$plist_path" >>"$LOG_FILE" 2>&1; then
    step_fail "Daemon: launchctl bootstrap failed"
    echo "    See $LOG_FILE for details." >&2
    exit 1
  fi

  step_ok "Daemon installed and loaded ($plist_path)"
  echo "    Note: daemon warm-up may play a short test phrase in the model's" >&2
  echo "    default voice once, the first time it starts." >&2
  echo "    WARNING: known upstream bug: vox daemon ignores voice setting" >&2
  echo "    (always Chelsie) and is slower than direct generation" >&2
  echo "    (8-9s vs ~6s). Not recommended." >&2
  return 0
}

# ---------------------------------------------------------------------------
# Step 3b: voice clone (optional). Runs before voice config so the clone
# name is a valid voice when it is set.
# ---------------------------------------------------------------------------

step_add_clone() {
  local vox
  vox="$(resolve_vox_bin)"

  if [ -z "$CLONE_AUDIO" ] || [ ! -f "$CLONE_AUDIO" ]; then
    step_fail "Clone '$CLONE_NAME': --clone-audio must point to an existing audio file"
    exit 1
  fi

  # Re-running with the same name replaces the clone; a missing clone is fine.
  "$vox" clone remove "$CLONE_NAME" >>"$LOG_FILE" 2>&1

  if [ -n "$CLONE_TEXT" ]; then
    if ! "$vox" clone add "$CLONE_NAME" --audio "$CLONE_AUDIO" --text "$CLONE_TEXT" >>"$LOG_FILE" 2>&1; then
      step_fail "vox clone add $CLONE_NAME failed"
      exit 1
    fi
  elif ! "$vox" clone add "$CLONE_NAME" --audio "$CLONE_AUDIO" >>"$LOG_FILE" 2>&1; then
    step_fail "vox clone add $CLONE_NAME failed"
    exit 1
  fi

  step_ok "Voice clone '$CLONE_NAME' registered ($CLONE_AUDIO)"
  return 0
}

# ---------------------------------------------------------------------------
# Step 5b: Claude Code integration (optional)
# ---------------------------------------------------------------------------

install_hook_script() {
  local script_dir
  local local_hook

  mkdir -p "$(dirname "$HOOK_PATH")" 2>>"$LOG_FILE"

  # Prefer the copy next to install.sh (clone checkout); fall back to GitHub
  # when piped through curl, where there is no sibling file.
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
  local_hook="${VOXUP_HOOK_SRC:-$script_dir/hooks/vox-speak-stop.sh}"
  if [ -f "$local_hook" ]; then
    cp "$local_hook" "$HOOK_PATH" 2>>"$LOG_FILE" || return 1
  else
    curl -fsSL "$HOOK_URL" -o "$HOOK_PATH" >>"$LOG_FILE" 2>&1 || return 1
  fi

  chmod +x "$HOOK_PATH" 2>>"$LOG_FILE" || return 1
  return 0
}

register_stop_hook() {
  # Idempotent merge into settings.json: add one Stop hook entry pointing at
  # HOOK_PATH unless an entry with that command already exists. A timestamped
  # backup is written before any change.
  python3 - "$CLAUDE_DIR/settings.json" "$HOOK_PATH" <<'PYEOF' 2>>"$LOG_FILE"
import json, os, shutil, sys, time

settings_path, hook_path = sys.argv[1], sys.argv[2]
settings = {}
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)

stop = settings.setdefault("hooks", {}).setdefault("Stop", [])
for group in stop:
    for hook in group.get("hooks", []):
        if hook.get("command") == hook_path:
            print("present")
            sys.exit(0)

if os.path.exists(settings_path):
    shutil.copy2(settings_path, "%s.voxup-bak-%d" % (settings_path, int(time.time())))

stop.append({"hooks": [{"type": "command", "command": hook_path, "timeout": 10}]})
os.makedirs(os.path.dirname(settings_path), exist_ok=True)
tmp = settings_path + ".voxup-tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(tmp, settings_path)
print("added")
PYEOF
  return $?
}

step_claude() {
  local vox
  local result
  vox="$(resolve_vox_bin)"

  if ! install_hook_script; then
    step_fail "Claude: failed to install hook script at $HOOK_PATH"
    exit 1
  fi

  if ! result="$(register_stop_hook)"; then
    step_fail "Claude: failed to update $CLAUDE_DIR/settings.json (see $LOG_FILE)"
    exit 1
  fi
  step_ok "Claude Stop hook $result ($HOOK_PATH)"

  if ! command -v claude >/dev/null 2>>"$LOG_FILE"; then
    step_fail "Claude: 'claude' CLI not found, skipped MCP registration"
    return 0
  fi
  if claude mcp get vox >>"$LOG_FILE" 2>&1; then
    step_ok "Claude MCP server 'vox' (already registered)"
    return 0
  fi
  if ! claude mcp add --scope user vox -- "$vox" serve >>"$LOG_FILE" 2>&1; then
    step_fail "Claude: 'claude mcp add vox' failed"
    exit 1
  fi
  step_ok "Claude MCP server 'vox' registered (user scope)"
  return 0
}

# ---------------------------------------------------------------------------
# Step 6: verify
# ---------------------------------------------------------------------------

step_verify() {
  local vox
  vox="$(resolve_vox_bin)"

  if ! "$vox" "voxup install complete" >>"$LOG_FILE" 2>&1; then
    step_fail "Verification: vox failed to speak test phrase"
    echo "    See $LOG_FILE for details." >&2
    exit 1
  fi

  step_ok "Verification (vox spoke the test phrase)"
  return 0
}

print_summary() {
  echo ""
  echo "voxup summary:"
  echo "  backend: qwen"
  echo "  lang:    en"
  echo "  voice:   $VOICE"
  if [ -n "$PACK" ]; then
    echo "  pack:    $PACK"
  else
    echo "  pack:    none"
  fi
  if [ "$DAEMON" -eq 1 ]; then
    echo "  daemon:  installed and loaded"
  else
    echo "  daemon:  not installed"
  fi
  if [ "$CLAUDE" -eq 1 ]; then
    echo "  claude:  Stop hook + MCP server"
  else
    echo "  claude:  not wired"
  fi
  echo "  log:     $LOG_FILE"
  return 0
}

# ---------------------------------------------------------------------------
# Doctor mode: re-check, do not mutate anything
# ---------------------------------------------------------------------------

run_doctor() {
  echo "voxup doctor: read-only checks, no changes will be made"
  echo ""

  if check_macos_arm; then
    step_ok "macOS on Apple Silicon (arm64)"
  else
    step_fail "macOS on Apple Silicon (arm64) - required, not detected"
  fi

  if check_homebrew; then
    step_ok "homebrew present ($(command -v brew))"
  else
    step_fail "homebrew not found"
  fi

  if check_vox_installed; then
    step_ok "vox present ($(resolve_vox_bin))"
  else
    step_fail "vox not found (expected at $VOX_BIN or on PATH)"
  fi

  if python3 -c "import mlx_audio" >/dev/null 2>&1; then
    step_ok "mlx-audio importable via python3"
  else
    step_fail "mlx-audio not importable via python3"
  fi

  if command -v python3 >/dev/null 2>&1; then
    step_ok "python3 present ($(command -v python3))"
  else
    step_fail "python3 not found"
  fi

  local vox
  vox="$(resolve_vox_bin)"
  if [ -n "$vox" ] && "$vox" config show >/dev/null 2>&1; then
    step_ok "vox config readable"
  else
    step_fail "vox config not readable (vox missing or config command failed)"
  fi

  local plist_label
  local plist_path
  plist_label="com.$(id -un).vox-daemon"
  plist_path="$HOME/Library/LaunchAgents/${plist_label}.plist"
  if [ -f "$plist_path" ]; then
    if launchctl print "gui/$(id -u)/${plist_label}" >/dev/null 2>&1; then
      step_ok "vox daemon plist present and loaded ($plist_path)"
    else
      step_fail "vox daemon plist present but not loaded ($plist_path)"
    fi
  else
    step_ok "vox daemon not installed (optional, plist absent)"
  fi

  if [ -n "$vox" ]; then
    echo "    voice clones: $("$vox" clone list 2>/dev/null | cut -d: -f1 | tr '\n' ' ')"
  fi

  if [ -x "$HOOK_PATH" ] && grep -q "$HOOK_PATH" "$CLAUDE_DIR/settings.json" 2>/dev/null; then
    step_ok "Claude Stop hook installed ($HOOK_PATH)"
  else
    step_ok "Claude Stop hook not installed (optional, use --claude)"
  fi

  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  : > "$LOG_FILE" 2>/dev/null || true
  log "voxup install.sh starting, args: $*"

  parse_args "$@"

  if [ "$SHOW_HELP" -eq 1 ]; then
    usage
    exit 0
  fi

  if [ "$DOCTOR" -eq 1 ]; then
    run_doctor
    exit 0
  fi

  step_preflight
  step_mlx_audio

  if [ -n "$CLONE_NAME" ]; then
    step_add_clone
  fi

  step_configure_voice

  if [ -n "$PACK" ]; then
    step_install_pack "$PACK"
  fi

  if [ "$DAEMON" -eq 1 ]; then
    step_install_daemon
  fi

  if [ "$CLAUDE" -eq 1 ]; then
    step_claude
  fi

  step_verify
  print_summary

  return 0
}

main "$@"
