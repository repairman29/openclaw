---
summary: "Master index of OpenClaw documentation and source modules"
read_when:
  - Finding docs for a specific feature or module
  - Auditing documentation coverage
title: "Documentation Index"
---

# Documentation Index

This index maps major source areas to their documentation. Use it to find where each part of the project is documented.

## Source → Docs mapping

| Source area      | Docs                                                                                                      |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| `src/cli/*`      | [CLI reference](/cli) — per-command pages (agent, gateway, message, cron, etc.)                           |
| `src/gateway/*`  | [Gateway](/gateway), [Protocol](/gateway/protocol), [Configuration](/gateway/configuration)               |
| `src/agents/*`   | [Agent concepts](/concepts/agent), [Pi runtime](/concepts/agent), [Session tools](/concepts/session-tool) |
| `src/telegram/*` | [Telegram channel](/channels/telegram)                                                                    |
| `src/discord/*`  | [Discord channel](/channels/discord)                                                                      |
| `src/slack/*`    | [Slack channel](/channels/slack)                                                                          |
| `src/web/*`      | [WebChat](/web/webchat), [Control UI](/web/control-ui)                                                    |
| `ui/src/*`       | [Control UI](/web/control-ui), [Web index](/web/index)                                                    |
| `src/cron/*`     | [Cron jobs](/automation/cron-jobs), [Cron vs Heartbeat](/automation/cron-vs-heartbeat)                    |
| `src/hooks/*`    | [Hooks](/automation/hooks), [Webhook](/automation/webhook)                                                |
| `src/plugins/*`  | [Plugins](/plugins/manifest), [Plugin SDK](/plugins)                                                      |
| `src/browser/*`  | [Browser tool](/tools/browser)                                                                            |
| `src/memory/*`   | [Memory](/concepts/memory)                                                                                |
| `src/wizard/*`   | [Wizard](/start/wizard), [Onboarding](/start/onboarding)                                                  |
| `scripts/*`      | [Scripts](/help/scripts), [Auth monitoring](/automation/auth-monitoring)                                  |
| `extensions/*`   | Per-extension README + [Channels](/channels), [Plugins](/plugins)                                         |

## Doc categories

- **Start**: [Getting started](/start/getting-started), [Wizard](/start/wizard), [Onboarding](/start/onboarding)
- **Install**: [Node](/install/node), [Docker](/install/docker), [Nix](/install/nix), [Updating](/install/updating)
- **Gateway**: [Architecture](/concepts/architecture), [Configuration](/gateway/configuration), [Remote](/gateway/remote), [Tailscale](/gateway/tailscale)
- **Channels**: [Index](/channels), per-channel pages (WhatsApp, Telegram, Discord, Slack, etc.)
- **Automation**: [Cron](/automation/cron-jobs), [Heartbeat](/gateway/heartbeat), [Hooks](/automation/hooks), [Webhook](/automation/webhook)
- **Tools**: [Browser](/tools/browser), [Skills](/tools/skills), [Exec approvals](/tools/exec-approvals)
- **Platforms**: [macOS](/platforms/macos), [iOS](/platforms/ios), [Android](/platforms/android), [Pi](/pi)
- **Reference**: [RPC](/reference/rpc), [Templates](/reference/templates), [Releasing](/reference/RELEASING)

## Adding docs

When adding new features or modules:

1. Add or update the relevant doc under `docs/`.
2. Add an entry to this index if it introduces a new source area.
3. Link from the doc to related pages using root-relative paths (e.g. `[Config](/gateway/configuration)`).
