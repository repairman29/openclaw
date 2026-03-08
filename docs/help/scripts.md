---
summary: "Repository scripts: purpose, scope, and safety notes"
read_when:
  - Running scripts from the repo
  - Adding or changing scripts under ./scripts
title: "Scripts"
---

# Scripts

The `scripts/` directory contains helper scripts for local workflows and ops tasks.
Use these when a task is clearly tied to a script; otherwise prefer the CLI.

## Conventions

- Scripts are **optional** unless referenced in docs or release checklists.
- Prefer CLI surfaces when they exist (example: auth monitoring uses `openclaw models status --check`).
- Assume scripts are host‑specific; read them before running on a new machine.

## Script inventory (by category)

### Auth and monitoring

- `auth-monitor.sh` — auth status checks; see [Auth monitoring](/automation/auth-monitoring)
- `claude-auth-status.sh` — Claude/OAuth auth status

### Build and packaging

- `build-and-run-mac.sh` — build and run macOS app locally
- `build_icon.sh` — generate app icon assets
- `bundle-a2ui.sh` — bundle A2UI for Canvas host
- `canvas-a2ui-copy.ts` — copy A2UI bundle into dist
- `package-mac-app.sh` — package macOS app for distribution
- `package-mac-dist.sh` — create distributable artifacts
- `create-dmg.sh` — create DMG installer
- `codesign-mac-app.sh` — code-sign macOS app
- `notarize-mac-artifact.sh` — notarize for Gatekeeper
- `make_appcast.sh` — generate Sparkle appcast

### CI and checks

- `ci-changed-scope.mjs` — determine CI scope from changed files
- `check-*.mjs` / `check-*.ts` — boundary checks (channel-agnostic, pairing, plugin SDK, etc.)
- `check-ts-max-loc.ts` — enforce max lines per file
- `pre-commit` — run pre-commit hooks (lint, format, tests)

### Docs and i18n

- `build-docs-list.mjs` — build docs list for Mintlify
- `docs-list.js` — docs list data
- `docs-link-audit.mjs` — audit internal doc links
- `docs-spellcheck.sh` — spellcheck docs
- `docs-i18n` — i18n pipeline for zh-CN translations

### Release and maintenance

- `release-check.ts` — pre-release validation
- `changelog-to-html.sh` — convert changelog to HTML
- `ghsa-patch.mjs` — patch GitHub security advisories
- `recover-orphaned-processes.sh` — recover stuck processes

### Development and debugging

- `dev` — dev server helpers
- `clawlog.sh` — query macOS unified logs for OpenClaw
- `restart-mac.sh` — restart macOS gateway via app
- `debug-claude-usage.ts` — debug Claude API usage
- `cron_usage_report.ts` — cron job usage report

### Install and platform

- `install.sh` — main install script (served from openclaw.ai)
- `install.ps1` — Windows install script
- `ios-configure-signing.sh` — configure iOS code signing
- `ios-team-id.sh` — look up iOS Team ID
- `run-openclaw-podman.sh` — run OpenClaw in Podman

### PR and repo ops

- `pr`, `pr-merge`, `pr-prepare`, `pr-review` — PR workflow helpers
- `committer` — create scoped commits
- `label-open-issues.ts` — label open issues

### Protocol and codegen

- `protocol-gen.ts` — generate protocol schemas
- `protocol-gen-swift.ts` — generate Swift models from protocol

### Sandbox and Docker

- `sandbox-*.sh` — browser sandbox setup
- `docker` — Docker test helpers
- `podman` — Podman helpers

### Other

- `run-node.mjs` — run Node scripts with tsx
- `mobile-reauth.sh` — mobile reauth flow
- `generate-*.mjs` — codegen (host env policy, secretref matrix)
- `firecrawl-compare.ts`, `readability-basic-compare.ts` — comparison utilities

## Auth monitoring scripts

Auth monitoring scripts are documented here:
[/automation/auth-monitoring](/automation/auth-monitoring)

## When adding scripts

- Keep scripts focused and documented.
- Add a short entry in the relevant doc (or create one if missing).
