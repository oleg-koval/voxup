# voxup

One-command sane setup for `vox` (the `vox` TTS CLI, installed via Homebrew at
`/opt/homebrew/bin/vox`) on Apple Silicon macOS: a neural English voice,
optional fun game sound packs, and an optional persistent background daemon.

## Quickstart

```bash
curl -fsSL <raw-url-placeholder>/install.sh | bash
```

Or clone and run locally:

```bash
git clone <repo-url-placeholder>
cd voxup
./install.sh
```

## Flags

| Flag              | Default  | Description                                                              |
|-------------------|----------|---------------------------------------------------------------------------|
| `--voice <name>`  | `Ethan`  | Voice to configure. Valid: `Chelsie` (f), `Ethan` (m), `Vivian` (f)       |
| `--pack <name>`   | none     | Install and set a game sound pack (see valid names below)                |
| `--daemon`        | off      | Install and load a persistent vox background daemon via launchd          |
| `--doctor`        | off      | Re-check prerequisites and print diagnostics, makes no changes           |
| `--help`          | -        | Show usage and exit                                                      |

Valid `--pack` names: `peon`, `peon_fr`, `peon_pl`, `peasant`, `peasant_fr`,
`sc_kerrigan`, `sc_battlecruiser`, `ra2_soviet_engineer`.

Each step prints one line (`OK`/`X`). Sub-tool noise is redirected to
`/tmp/voxup-install.log`.

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

## Uninstall

```bash
# stop and remove the daemon, if installed
launchctl bootout gui/$(id -u)/com.$(id -un).vox-daemon
rm -f ~/Library/LaunchAgents/com.$(id -un).vox-daemon.plist

# reset vox configuration
vox config reset
```

Sound pack files installed under
`~/Library/Application Support/vox/packs/<pack>/` can be removed manually if
desired.

## Note on pack audio licensing

Sound pack audio is fetched at install time directly from the `peon-ping`
GitHub repository. It is CC-BY-NC-4.0 licensed game audio and is **not**
redistributed in this repository; voxup only downloads it on demand into your
local vox configuration directory.
