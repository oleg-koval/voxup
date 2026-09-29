# voxup

[![ci](https://github.com/oleg-koval/voxup/actions/workflows/ci.yml/badge.svg)](https://github.com/oleg-koval/voxup/actions/workflows/ci.yml)

One-command sane setup for `vox` (the `vox` TTS CLI, installed via Homebrew at
`/opt/homebrew/bin/vox`) on Apple Silicon macOS: a neural English voice,
optional fun game sound packs, and an optional persistent background daemon.

## Quickstart

```bash
curl -fsSL https://raw.githubusercontent.com/oleg-koval/voxup/main/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/oleg-koval/voxup
cd voxup
./install.sh
```

## Flags

| Flag              | Default  | Description                                                              |
|-------------------|----------|---------------------------------------------------------------------------|
| `--voice <name>`  | `Ethan`  | Voice to configure. Valid: `Chelsie` (f), `Ethan` (m), `Vivian` (f)       |
| `--pack <name>`   | none     | Install and set a game sound pack (see valid names below)                |
| `--daemon`        | off      | Install and load a persistent vox background daemon via launchd. WARNING: known upstream bug, see Known upstream issues below. Not recommended. |
| `--clone <name>`  | none     | Register a voice clone with `vox clone add` and use it as the voice. Needs `--clone-audio`. |
| `--clone-audio <wav>` | -    | Reference audio for `--clone` (a few clean seconds of speech)            |
| `--clone-text <text>` | -    | Transcript of the reference audio; improves clone quality                |
| `--claude`        | off      | Wire vox into Claude Code: register the `vox` MCP server and add a Stop hook that speaks each final reply. See below. |
| `--doctor`        | off      | Re-check prerequisites and print diagnostics, makes no changes           |
| `--help`          | -        | Show usage and exit                                                      |

Valid `--pack` names: `peon`, `peon_fr`, `peon_pl`, `peasant`, `peasant_fr`,
`sc_kerrigan`, `sc_battlecruiser`, `ra2_soviet_engineer`.

Each step prints one line (`OK`/`X`). Sub-tool noise is redirected to
`/tmp/voxup-install.log`.

## Recommended setup

```bash
./install.sh --voice Ethan --pack sc_battlecruiser --claude
```

Qwen3-TTS (`mlx-community/Qwen3-TTS-12Hz-0.6B-Base`, runs locally via
mlx-audio) with the male Ethan speaker, StarCraft battlecruiser sound pack,
no daemon, and Claude Code speaking the first line of every reply.

To speak in a cloned voice instead, add a reference clip:

```bash
./install.sh --clone gandalf --clone-audio ~/voice/gandalf.wav \
  --clone-text "Exact words spoken in the clip." --claude
```

Reference clips are personal files and are never stored in this repo.

## Claude Code integration (`--claude`)

`--claude` does two things, both idempotent:

1. Registers the MCP server (`claude mcp add --scope user vox -- vox serve`)
   unless one named `vox` already exists, so Claude can call `vox_speak`.
2. Installs `hooks/vox-speak-stop.sh` to `~/.claude/hooks/` and adds it as a
   `Stop` hook in `~/.claude/settings.json` (existing hooks are kept, a
   timestamped `settings.json.voxup-bak-*` backup is written first).

When a turn ends, the hook takes the first line of Claude's final reply,
strips markdown, and speaks it in the background. It never blocks or fails
the session. With the hook in place you no longer need a "call vox speak
after every task" line in `CLAUDE.md`; remove it to avoid hearing each
summary twice.

Tune it with environment variables (set them in the `env` block of
`settings.json`):

| Variable               | Effect                                                        |
|------------------------|---------------------------------------------------------------|
| `VOXUP_SPEAK=0`        | Mute without removing the hook                                |
| `VOXUP_SPEAK_PATTERN`  | Only speak lines matching this regex, e.g. `^(DONE\|NEEDS-YOU\|BLOCKED):` |
| `VOXUP_SPEAK_MAX`      | Truncate spoken text (default 200 characters)                 |

Note: the vox MCP server's own instructions tell Claude to speak French by
default. voxup sets `lang en`; if Claude still answers in French, say
"always speak English" in your `CLAUDE.md`.

## Known upstream issues this works around

1. **Broken pack installer URL.** `vox pack install` 404s because it hardcodes
   the old `tonyyont/peon-ping` repo. Packs moved to `PeonPing/og-packs` with a
   new CESP `openpeon.json` manifest format that vox does not speak yet.
   voxup instead downloads packs directly from the last pre-move commit of
   `PeonPing/peon-ping` (`cb09d49adad4e79618e3b599a35974d542ed75a7`), lays out
   `manifest.json` plus a `sounds/` subdirectory under
   `~/Library/Application Support/vox/packs/<pack>/` (vox's playback code
   requires the `sounds/` subdir even though the manifest lists bare
   filenames), then runs `vox pack set <pack>`.

2. **Wrong voice list.** vox advertises qwen voices `Chelsie`/`Aidan`/`Luna`/`Ryan`,
   but the actual Qwen3-TTS-12Hz-0.6B-Base speakers are only `Chelsie` (f),
   `Ethan` (m), and `Vivian` (f). Any other name silently falls back to female
   `Chelsie` inside vox with no warning. voxup validates `--voice` against the
   real list and rejects anything else with a clear message.

3. **`daemon _run`, not `daemon run`.** The persistent-daemon subcommand is
   `vox daemon _run` (leading underscore). `vox daemon run` does not exist and
   will crash-loop launchd if used in a LaunchAgent. voxup's generated plist
   uses the correct `_run` subcommand.

4. **Daemon ignores the configured voice, and is slower.** When the vox
   daemon (`vox daemon _run`) is running, `vox speak` requests are routed
   through it instead of generating directly. The daemon ignores whatever
   voice was configured and always speaks as the female `Chelsie` speaker of
   Qwen3-TTS, with no warning. It is also slower than direct generation
   (roughly 8-9s per utterance vs roughly 6s without the daemon). `--daemon`
   is kept for anyone who explicitly wants the persistent background process,
   but it is **not recommended** until this is fixed upstream. voxup prints a
   warning whenever `--daemon` is used.

## Uninstall

```bash
# stop and remove the daemon, if installed
launchctl bootout gui/$(id -u)/com.$(id -un).vox-daemon
rm -f ~/Library/LaunchAgents/com.$(id -un).vox-daemon.plist

# reset vox configuration
vox config reset

# Claude Code: remove the MCP server and the hook
claude mcp remove vox -s user
rm -f ~/.claude/hooks/vox-speak-stop.sh
# then delete the vox-speak-stop.sh entry under hooks.Stop in ~/.claude/settings.json
```

Sound pack files installed under
`~/Library/Application Support/vox/packs/<pack>/` can be removed manually if
desired.

## Note on pack audio licensing

Sound pack audio is fetched at install time directly from the `peon-ping`
GitHub repository. It is CC-BY-NC-4.0 licensed game audio and is **not**
redistributed in this repository; voxup only downloads it on demand into your
local vox configuration directory.
