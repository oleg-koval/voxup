#!/usr/bin/env bash
#
# Tests for the --claude integration: settings.json merge and the Stop hook's
# text extraction. Uses a stub vox and a temp CLAUDE_CONFIG_DIR, so it never
# touches the real ~/.claude or speaks. Runs on macOS and Linux (CI).

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILS=0

check() {
  # $1 = description, $2 = expected, $3 = actual
  if [ "$2" = "$3" ]; then
    echo "OK  $1"
  else
    echo "X   $1"
    echo "    expected: $2"
    echo "    actual:   $3"
    FAILS=$((FAILS + 1))
  fi
  return 0
}

STUB="$TMP/stubvox"
SPOKEN="$TMP/spoken.txt"
cat >"$STUB" <<EOF
#!/usr/bin/env bash
shift
echo "\$*" >"$SPOKEN"
EOF
chmod +x "$STUB"

export CLAUDE_CONFIG_DIR="$TMP/claude"
mkdir -p "$CLAUDE_CONFIG_DIR"
echo '{"model":"x","hooks":{"Stop":[{"hooks":[{"type":"command","command":"other.sh"}]}]}}' >"$CLAUDE_CONFIG_DIR/settings.json"

# Load install.sh functions without running main.
sed '$d' "$REPO/install.sh" >"$TMP/lib.sh"
# shellcheck disable=SC1091
. "$TMP/lib.sh"
# shellcheck disable=SC2034 # read by the sourced install.sh functions
LOG_FILE="$TMP/install.log"
export VOXUP_HOOK_SRC="$REPO/hooks/vox-speak-stop.sh"

install_hook_script || echo "install_hook_script failed"
check "hook script installed and executable" "yes" "$([ -x "$HOOK_PATH" ] && echo yes || echo no)"

check "first merge adds the hook" "added" "$(register_stop_hook)"
check "second merge is a no-op" "present" "$(register_stop_hook)"
check "existing Stop hook kept, ours appended once" \
  "other.sh $HOOK_PATH" \
  "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(" ".join(h["command"] for g in d["hooks"]["Stop"] for h in g["hooks"]))' "$CLAUDE_CONFIG_DIR/settings.json")"
check "unrelated settings kept" "x" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["model"])' "$CLAUDE_CONFIG_DIR/settings.json")"
check "one backup written" "1" "$(find "$CLAUDE_CONFIG_DIR" -name 'settings.json.voxup-bak-*' | wc -l | tr -d ' ')"

run_hook() {
  # $1 = payload JSON; extra env vars are passed through by the caller
  : >"$SPOKEN"
  printf '%s' "$1" | VOXUP_VOX_BIN="$STUB" "$HOOK_PATH"
  # speech is detached; give the stub a moment to write
  local i=0
  while [ ! -s "$SPOKEN" ] && [ "$i" -lt 20 ]; do
    perl -e 'select(undef,undef,undef,0.05)'
    i=$((i + 1))
  done
  cat "$SPOKEN"
  return 0
}

# shellcheck disable=SC2016 # backticks are literal markdown in the payload
check "speaks first line, markdown stripped" \
  "DONE: hook wired via PR" \
  "$(run_hook '{"last_assistant_message":"\n**DONE:** hook `wired` via [PR](http://x)\nmore"}')"

printf '%s\n' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"- NEEDS-YOU: pick a voice"}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"x"}]}}' >"$TMP/tr.jsonl"
check "falls back to transcript, skips tool-only entries" \
  "NEEDS-YOU: pick a voice" \
  "$(run_hook "{\"transcript_path\":\"$TMP/tr.jsonl\"}")"

check "pattern filters non-matching lines" "" \
  "$(VOXUP_SPEAK_PATTERN='^(DONE|NEEDS-YOU|BLOCKED):' run_hook '{"last_assistant_message":"hello there"}')"
check "VOXUP_SPEAK=0 disables" "" \
  "$(VOXUP_SPEAK=0 run_hook '{"last_assistant_message":"hello"}')"
check "stop_hook_active is ignored" "" \
  "$(run_hook '{"last_assistant_message":"x","stop_hook_active":true}')"
check "garbage payload is silent" "" "$(run_hook 'not json')"
printf 'not json' | VOXUP_VOX_BIN="$STUB" "$HOOK_PATH"
check "garbage payload exits 0" "0" "$?"

if [ "$FAILS" -gt 0 ]; then
  echo "$FAILS check(s) failed"
  exit 1
fi
echo "all checks passed"
exit 0
