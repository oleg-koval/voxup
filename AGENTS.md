# AGENTS.md

This repo follows `oleg-koval/starters` `RULES.md`.

## Documented exemption: §2.2 (300-line file cap)

`install.sh` is intentionally a single file (currently ~750 lines) so it can
be piped straight from GitHub with:

```bash
curl -fsSL <raw-url> | bash
```

Splitting it into multiple files would break that usage. Do not split it.

## Lint / format gates

- `shellcheck install.sh hooks/*.sh tests/*.sh`
- `shfmt -d install.sh hooks/*.sh tests/*.sh`
- `bash tests/test-claude-hook.sh`

Run via `make lint` and `make test`.

`hooks/vox-speak-stop.sh` is a separate file so it can be linted and tested;
`install.sh` copies it from the checkout, or downloads it from `main` when
piped through curl.

## Style

Functions use explicit `return` statements; no implicit returns.
