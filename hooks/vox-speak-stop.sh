#!/usr/bin/env bash
#
# vox-speak-stop.sh - Claude Code Stop hook installed by voxup.
#
# When Claude finishes a turn, speak the first line of its final reply with
# vox. Reads the hook payload on stdin, never blocks the session: speech runs
# detached and every failure exits 0 silently.
#
# Environment:
#   VOXUP_SPEAK=0            disable speaking without removing the hook
#   VOXUP_SPEAK_PATTERN=re   only speak lines matching this extended regex,
#                            e.g. '^(DONE|NEEDS-YOU|BLOCKED):'
#   VOXUP_SPEAK_MAX=200      truncate spoken text to this many characters
#   VOXUP_VOX_BIN=path       vox binary (default /opt/homebrew/bin/vox)

if [ "${VOXUP_SPEAK:-1}" = "0" ]; then
  exit 0
fi

VOX_BIN="${VOXUP_VOX_BIN:-/opt/homebrew/bin/vox}"
if [ ! -x "$VOX_BIN" ]; then
  VOX_BIN="$(command -v vox 2>/dev/null)"
fi
if [ -z "$VOX_BIN" ]; then
  exit 0
fi

# Extract the first meaningful line of the last assistant reply. Prefer the
# payload's last_assistant_message; fall back to scanning the transcript.
line="$(VOXUP_SPEAK_MAX="${VOXUP_SPEAK_MAX:-200}" python3 -c '
import json, os, re, sys

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if payload.get("stop_hook_active"):
    sys.exit(0)

text = payload.get("last_assistant_message") or ""

if not text:
    path = payload.get("transcript_path") or ""
    try:
        with open(os.path.expanduser(path)) as f:
            lines = f.readlines()
    except Exception:
        sys.exit(0)
    for raw in reversed(lines):
        try:
            entry = json.loads(raw)
        except Exception:
            continue
        if entry.get("type") != "assistant" or entry.get("isSidechain"):
            continue
        content = (entry.get("message") or {}).get("content") or []
        if isinstance(content, str):
            content = [{"type": "text", "text": content}]
        parts = [b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"]
        if any(p.strip() for p in parts):
            text = "\n".join(parts)
            break

for candidate in text.splitlines():
    candidate = re.sub(r"[`*_#>|]", "", candidate).strip()
    candidate = re.sub(r"^[-+]\s+", "", candidate)
    candidate = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", candidate)
    if candidate:
        limit = int(os.environ.get("VOXUP_SPEAK_MAX", "200"))
        print(candidate[:limit])
        break
' 2>/dev/null)"

if [ -z "$line" ]; then
  exit 0
fi

if [ -n "${VOXUP_SPEAK_PATTERN:-}" ]; then
  if ! printf '%s\n' "$line" | grep -Eq "$VOXUP_SPEAK_PATTERN"; then
    exit 0
  fi
fi

nohup "$VOX_BIN" -- "$line" >/dev/null 2>&1 &
exit 0
