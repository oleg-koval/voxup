# AGENTS.md

This repo follows `oleg-koval/starters` `RULES.md`.

## Documented exemption: §2.2 (300-line file cap)

`install.sh` is intentionally a single file (currently ~400 lines) so it can
be piped straight from GitHub with:

```bash
curl -fsSL <raw-url> | bash
```

Splitting it into multiple files would break that usage. Do not split it.

## Lint / format gates

- `shellcheck install.sh`
- `shfmt -d install.sh`

Run both via `make lint`.

## Style

Functions use explicit `return` statements; no implicit returns.
