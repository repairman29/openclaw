# SwiftUI for MacBook: Improvements & Enhancements

Recommendations for **ChumpMenu** (rust-agent/ChumpMenu) and the **OpenClaw macOS** menubar app (apps/macos). Mix of functional, UX, and visual improvements.

---

## ChumpMenu (Chump menu bar app)

### Functional

- **Configurable repo path in UI** – Today `ChumpRepoPath` is only via `UserDefaults` (no UI). Add a Settings section or “Set rust-agent path…” that opens a folder picker and saves to UserDefaults so users can point at a different clone.
- **Start Chump in background** – “Start Chump” currently runs `run-discord.sh` in a way that may tie to the launching shell. Run it truly detached (e.g. `nohup` / `launchd`-style) so closing the menu doesn’t affect the bot, and show “Chump starting…” until the first refresh sees the process.
- **Heartbeat duration / quick test** – Add a control (e.g. “Start heartbeat (quick 2m)” vs “Start heartbeat (8h)”) or a small preferences row so power users can run `HEARTBEAT_QUICK_TEST=1` from the menu.
- **Autonomy tier in menu** – If `logs/autonomy-tier.env` exists, read `CHUMP_AUTONOMY_TIER` and show “Autonomy: Tier N” (or “Certified”) in the status area so users see that tests have been run.
- **Run autonomy tests** – Add “Run autonomy tests” that runs `scripts/run-autonomy-tests.sh` (in background or with a small progress indicator) and opens the log when done.
- **Which model on 8000** – Port status is “warm/cold”; optionally show “30B” vs “7B” (e.g. by calling `/v1/models` and parsing the model id, or from a small cache file written by the serve script).
- **Last error / toast** – When start fails (e.g. script not found, embed failed), show a short-lived in-window toast or inline message instead of only a modal alert, so the menu doesn’t block.
- **Refresh on demand** – Keep the 10s timer; add a “Refresh” button or pull-to-refresh so users can force an immediate status update after starting something.

### Beautiful / UX

- **Grouped sections with headers** – Use `Section { } header: { }` (or equivalent) for “Status”, “Model servers”, “Embed”, “Chump”, “Heartbeat”, “Logs” so the list is scannable.
- **Icons for every row** – Add `Label("…", systemImage: "…")` (e.g. `server.rack`, `brain`, `waveform.path.ecg`, `doc.text`, `xmark.circle`) so the menu feels consistent and easier to scan.
- **Status colors and symbols** – Replace “8000: warm” with a small green dot + “8000” and “cold” with a gray dot; same for embed and Chump online/offline. Use SF Symbols (e.g. `circle.fill`) and semantic colors.
- **MenuBarExtra style** – Currently `.window`; consider trying `.menu` for a compact dropdown, or make it a preference (Window vs Menu style) for users who prefer a smaller footprint.
- **Min width and padding** – Increase `minWidth` slightly (e.g. 280–300) and use consistent horizontal padding so “Stop vLLM-MLX (8000)” doesn’t feel cramped; align status text to the leading edge with clear hierarchy.
- **Smoother refresh** – When `refresh()` runs, avoid visible flicker (e.g. use subtle opacity or a single update that doesn’t reset the whole list).
- **Accent color** – Use a single accent (e.g. Chump green or a brand color) for primary actions (Start Chump, Start heartbeat) so they stand out from “Open logs”.

---

## OpenClaw macOS app (menubar + Settings)

### Functional

- **Connection mode clarity** – In the menu, make “Local” vs “Remote” and “Unconfigured” obvious at a glance (icon or first line of status) so users know why the critter is “sleeping” or disabled. _Done: Connection section shows icon (network/cloud/exclamationmark.triangle) + label and color (green/blue/orange)._
- **Gateway not running recovery** – When status is “gateway not running”, add a one-tap “Start gateway” (or “Fix”) that runs the same logic as the keepalive/script so users don’t have to open Settings. _Done: “Start gateway” button in Connection section when local mode and gateway is stopped/failed; calls GatewayProcessManager.setActive(true)._
- **Heartbeat status detail** – Show next scheduled time or “Last sent X min ago” in the menu (from HeartbeatStore or gateway) so heartbeat isn’t a black box.
- **WebChat session switcher in menu** – Before opening chat, show a tiny session picker in the menu (e.g. “Open Chat (main)” / “Open Chat (other)”) or remember last session and offer “Open Chat” + “Switch session…”.
- **Voice Wake feedback in menu** – When Voice Wake is on, show “Listening” or “Ready” and maybe a mic level so users know the overlay isn’t stuck.
- **Cron / next job in menu** – Optional: one line “Cron: next at HH:MM” or “Cron idle” so power users don’t have to open Settings → Cron.
- **Tailscale / remote status** – If connection is remote, show “Remote (Tailscale)” or “Remote (URL)” and a small indicator that control channel is connected, so users trust the connection type.

### Beautiful / UX

- **Critter icon states** – Expand `CritterStatusLabel` / `IconState` with clearer “sleeping” vs “paused” vs “working” (e.g. different idle animation, or a small badge) so the menubar icon is self-explanatory.
- **Menu content hierarchy** – Use `Section` and consistent `Label(..., systemImage:)` for every menu item; group “Connection”, “Features”, “Quick actions”, “Settings” with subtle dividers and spacing. _Done: MenuContentView uses Section headers for Connection, Features, Quick actions, Settings; items already use Label(..., systemImage:)._
- **Settings tab order** – Consider putting the most-used tabs (General, Channels, Config) first and moving Debug/About to the end; or add a “Favorites” / recent tabs so returning users get there faster.
- **WebChat panel size** – Revisit `WebChatSwiftUILayout.panelSize` and min size on small screens; ensure the chat input and at least one message are always visible without resizing.
- **Consistent spacing and typography** – In Settings, use a single vertical rhythm (e.g. 8/12/16) and caption vs body so all tabs feel part of one app; align labels and controls on a clear grid.
- **Dark mode** – Ensure all custom colors (status pills, Critter, HoverHUD) have a dark-mode-friendly variant and that the WebChat theme follows system appearance if desired.
- **HoverHUD and overlays** – Make the voice overlay and any HUD feel “native” (blur, rounded corners, shadow) and ensure they don’t obscure critical UI; add a small “Dismiss” or timeout so they’re not permanent.
- **Onboarding** – If onboarding is shown, keep steps short and use illustrations or icons so the Mac app feels polished and not text-heavy; optional “Skip” for advanced users.

---

## Cross‑cutting (both apps)

- **Observation over ObservableObject** – Prefer `@Observable` / `@Bindable` for new state (per repo guidelines); migrate ChumpMenu’s `ChumpState` from `ObservableObject` to `@Observable` when touching that file.
- **Accessibility** – Add `accessibilityLabel` and `accessibilityHint` for status and buttons so VoiceOver users can operate the menu and understand “Chump online” vs “8000 warm”.
- **Localization** – If you ever ship to non‑English users, extract strings (e.g. “Chump online”, “Start vLLM-MLX (8000)”) so they can be localized later without refactoring.
- **Errors and logging** – Surface “why did start fail?” in the UI (e.g. “Script not found” vs “Permission denied”) and log to a known path (e.g. `~/Library/Logs/ChumpMenu/`) for support.

---

## Summary table

| Area          | ChumpMenu focus                                                    | OpenClaw focus                                          |
| ------------- | ------------------------------------------------------------------ | ------------------------------------------------------- |
| Functional    | Repo path UI, background start, autonomy tier, which model on 8000 | Gateway recovery, heartbeat/cron hint, session switcher |
| Beautiful/UX  | Sections, icons, status colors, accent                             | Critter states, menu hierarchy, WebChat size, dark mode |
| Cross‑cutting | @Observable, a11y, errors                                          | Same + localization readiness                           |

Use this as a backlog: pick a few items per release (e.g. “ChumpMenu: sections + icons + Start in background”) and iterate.
