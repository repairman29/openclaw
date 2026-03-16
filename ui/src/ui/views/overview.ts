import { html } from "lit";
import { ConnectErrorDetailCodes } from "../../../../src/gateway/protocol/connect-error-details.js";
import { t, i18n, SUPPORTED_LOCALES, type Locale } from "../../i18n/index.ts";
import type { ExecApprovalRequest } from "../controllers/exec-approval.ts";
import { buildExternalLinkRel, EXTERNAL_LINK_TARGET } from "../external-link.ts";
import { formatRelativeTimestamp, formatDurationHuman } from "../format.ts";
import type { GatewayHelloOk } from "../gateway.ts";
import { formatNextRun } from "../presenter.ts";
import type { UiSettings } from "../storage.ts";
import type {
  ChannelsStatusSnapshot,
  CronJob,
  CronRunLogEntry,
  DiscordStatus,
  GatewaySessionRow,
} from "../types.ts";
import { shouldShowPairingHint } from "./overview-hints.ts";

export type OverviewProps = {
  connected: boolean;
  hello: GatewayHelloOk | null;
  settings: UiSettings;
  password: string;
  lastError: string | null;
  lastErrorCode: string | null;
  presenceCount: number;
  sessionsCount: number | null;
  cronEnabled: boolean | null;
  cronNext: number | null;
  cronJobs: CronJob[];
  cronRuns: CronRunLogEntry[];
  sessionRows: GatewaySessionRow[];
  channelsSnapshot: ChannelsStatusSnapshot | null;
  lastChannelsRefresh: number | null;
  execApprovalQueue?: ExecApprovalRequest[];
  basePath?: string;
  onNavigateToNodes?: () => void;
  onNavigateToCron?: () => void;
  onSettingsChange: (next: UiSettings) => void;
  onPasswordChange: (next: string) => void;
  onSessionKeyChange: (next: string) => void;
  onConnect: () => void;
  onRefresh: () => void;
};

export function renderOverview(props: OverviewProps) {
  const nowMs = Date.now();
  const snapshot = props.hello?.snapshot as
    | {
        uptimeMs?: number;
        policy?: { tickIntervalMs?: number };
        authMode?: "none" | "token" | "password" | "trusted-proxy";
      }
    | undefined;
  const uptime = snapshot?.uptimeMs ? formatDurationHuman(snapshot.uptimeMs) : t("common.na");
  const tick = snapshot?.policy?.tickIntervalMs
    ? `${snapshot.policy.tickIntervalMs}ms`
    : t("common.na");
  const authMode = snapshot?.authMode;
  const isTrustedProxy = authMode === "trusted-proxy";

  const pairingHint = (() => {
    if (!shouldShowPairingHint(props.connected, props.lastError, props.lastErrorCode)) {
      return null;
    }
    return html`
      <div class="muted" style="margin-top: 8px">
        ${t("overview.pairing.hint")}
        <div style="margin-top: 6px">
          <span class="mono">openclaw devices list</span><br />
          <span class="mono">openclaw devices approve &lt;requestId&gt;</span>
        </div>
        <div style="margin-top: 6px; font-size: 12px;">
          ${t("overview.pairing.mobileHint")}
        </div>
        <div style="margin-top: 6px">
          <a
            class="session-link"
            href="https://docs.openclaw.ai/web/control-ui#device-pairing-first-connection"
            target=${EXTERNAL_LINK_TARGET}
            rel=${buildExternalLinkRel()}
            title="Device pairing docs (opens in new tab)"
            >Docs: Device pairing</a
          >
        </div>
      </div>
    `;
  })();

  const authHint = (() => {
    if (props.connected || !props.lastError) {
      return null;
    }
    const lower = props.lastError.toLowerCase();
    const authRequiredCodes = new Set<string>([
      ConnectErrorDetailCodes.AUTH_REQUIRED,
      ConnectErrorDetailCodes.AUTH_TOKEN_MISSING,
      ConnectErrorDetailCodes.AUTH_PASSWORD_MISSING,
      ConnectErrorDetailCodes.AUTH_TOKEN_NOT_CONFIGURED,
      ConnectErrorDetailCodes.AUTH_PASSWORD_NOT_CONFIGURED,
    ]);
    const authFailureCodes = new Set<string>([
      ...authRequiredCodes,
      ConnectErrorDetailCodes.AUTH_UNAUTHORIZED,
      ConnectErrorDetailCodes.AUTH_TOKEN_MISMATCH,
      ConnectErrorDetailCodes.AUTH_PASSWORD_MISMATCH,
      ConnectErrorDetailCodes.AUTH_DEVICE_TOKEN_MISMATCH,
      ConnectErrorDetailCodes.AUTH_RATE_LIMITED,
      ConnectErrorDetailCodes.AUTH_TAILSCALE_IDENTITY_MISSING,
      ConnectErrorDetailCodes.AUTH_TAILSCALE_PROXY_MISSING,
      ConnectErrorDetailCodes.AUTH_TAILSCALE_WHOIS_FAILED,
      ConnectErrorDetailCodes.AUTH_TAILSCALE_IDENTITY_MISMATCH,
    ]);
    const authFailed = props.lastErrorCode
      ? authFailureCodes.has(props.lastErrorCode)
      : lower.includes("unauthorized") || lower.includes("connect failed");
    if (!authFailed) {
      return null;
    }
    const hasToken = Boolean(props.settings.token.trim());
    const hasPassword = Boolean(props.password.trim());
    const isAuthRequired = props.lastErrorCode
      ? authRequiredCodes.has(props.lastErrorCode)
      : !hasToken && !hasPassword;
    if (isAuthRequired) {
      return html`
        <div class="muted" style="margin-top: 8px">
          ${t("overview.auth.required")}
          <div style="margin-top: 6px">
            <span class="mono">openclaw dashboard --no-open</span> → tokenized URL<br />
            <span class="mono">openclaw doctor --generate-gateway-token</span> → set token
          </div>
          <div style="margin-top: 6px">
            <a
              class="session-link"
              href="https://docs.openclaw.ai/web/dashboard"
              target=${EXTERNAL_LINK_TARGET}
              rel=${buildExternalLinkRel()}
              title="Control UI auth docs (opens in new tab)"
              >Docs: Control UI auth</a
            >
          </div>
        </div>
      `;
    }
    return html`
      <div class="muted" style="margin-top: 8px">
        ${t("overview.auth.failed", { command: "openclaw dashboard --no-open" })}
        <div style="margin-top: 6px">
          <a
            class="session-link"
            href="https://docs.openclaw.ai/web/dashboard"
            target=${EXTERNAL_LINK_TARGET}
            rel=${buildExternalLinkRel()}
            title="Control UI auth docs (opens in new tab)"
            >Docs: Control UI auth</a
          >
        </div>
      </div>
    `;
  })();

  const insecureContextHint = (() => {
    if (props.connected || !props.lastError) {
      return null;
    }
    const isSecureContext = typeof window !== "undefined" ? window.isSecureContext : true;
    if (isSecureContext) {
      return null;
    }
    const lower = props.lastError.toLowerCase();
    const insecureContextCode =
      props.lastErrorCode === ConnectErrorDetailCodes.CONTROL_UI_DEVICE_IDENTITY_REQUIRED ||
      props.lastErrorCode === ConnectErrorDetailCodes.DEVICE_IDENTITY_REQUIRED;
    if (
      !insecureContextCode &&
      !lower.includes("secure context") &&
      !lower.includes("device identity required")
    ) {
      return null;
    }
    return html`
      <div class="muted" style="margin-top: 8px">
        ${t("overview.insecure.hint", { url: "http://127.0.0.1:18789" })}
        <div style="margin-top: 6px">
          ${t("overview.insecure.stayHttp", { config: "gateway.controlUi.allowInsecureAuth: true" })}
        </div>
        <div style="margin-top: 6px">
          <a
            class="session-link"
            href="https://docs.openclaw.ai/gateway/tailscale"
            target=${EXTERNAL_LINK_TARGET}
            rel=${buildExternalLinkRel()}
            title="Tailscale Serve docs (opens in new tab)"
            >Docs: Tailscale Serve</a
          >
          <span class="muted"> · </span>
          <a
            class="session-link"
            href="https://docs.openclaw.ai/web/control-ui#insecure-http"
            target=${EXTERNAL_LINK_TARGET}
            rel=${buildExternalLinkRel()}
            title="Insecure HTTP docs (opens in new tab)"
            >Docs: Insecure HTTP</a
          >
        </div>
      </div>
    `;
  })();

  const currentLocale = i18n.getLocale();
  const channels = props.channelsSnapshot?.channels ?? null;
  const discord = (channels?.discord ?? null) as DiscordStatus | null;
  const discordAccounts = props.channelsSnapshot?.channelAccounts?.discord ?? [];
  const latestDiscordOutboundAt =
    discordAccounts
      .map((account) =>
        typeof account.lastOutboundAt === "number" ? account.lastOutboundAt : null,
      )
      .filter((value): value is number => value !== null)
      .toSorted((a, b) => b - a)[0] ?? null;
  const latestRunByJob = new Map<string, CronRunLogEntry>();
  for (const run of props.cronRuns) {
    const existing = latestRunByJob.get(run.jobId);
    if (!existing || run.ts > existing.ts) {
      latestRunByJob.set(run.jobId, run);
    }
  }
  const enabledCronJobs = props.cronJobs.filter((job) => job.enabled);
  const reliableCronJobs = enabledCronJobs.filter((job) => job.state?.lastStatus === "ok");
  const cronReliabilityPct =
    enabledCronJobs.length > 0
      ? Math.round((reliableCronJobs.length / enabledCronJobs.length) * 100)
      : null;
  const timeoutErrorCount = props.cronRuns.filter((run) => {
    const message = [run.error, run.summary].filter(Boolean).join(" ").toLowerCase();
    return message.includes("timeout") || message.includes("timed out");
  }).length;
  const timeoutRiskFromJobs = enabledCronJobs.filter((job) => {
    if (job.payload.kind !== "agentTurn") {
      return false;
    }
    return typeof job.payload.timeoutSeconds !== "number" || job.payload.timeoutSeconds <= 30;
  }).length;
  const timeoutRiskLabel =
    timeoutErrorCount > 0 ||
    timeoutRiskFromJobs > Math.max(1, Math.floor(enabledCronJobs.length / 2))
      ? "High"
      : timeoutRiskFromJobs > 0
        ? "Medium"
        : "Low";
  const discordDeliveryLabel = (() => {
    if (!discord?.configured) {
      return "Not configured";
    }
    if (!discord.running) {
      return "Stopped";
    }
    if (discord.probe && !discord.probe.ok) {
      return "Probe failed";
    }
    if (latestDiscordOutboundAt && nowMs - latestDiscordOutboundAt <= 6 * 60 * 60 * 1000) {
      return "Active";
    }
    return "Idle";
  })();
  const recentRuns = props.cronRuns.filter((run) => nowMs - run.ts <= 60 * 60 * 1000);
  const runs24h = props.cronRuns.filter((run) => nowMs - run.ts <= 24 * 60 * 60 * 1000);
  const successfulRuns24h = runs24h.filter((run) => run.status === "ok");
  const recentDeliveries = recentRuns.filter(
    (run) =>
      run.deliveryStatus &&
      run.deliveryStatus !== "not-requested" &&
      run.deliveryStatus !== "unknown",
  );
  const deliveries24h = runs24h.filter(
    (run) =>
      run.deliveryStatus &&
      run.deliveryStatus !== "not-requested" &&
      run.deliveryStatus !== "unknown",
  );
  const delivered24h = deliveries24h.filter((run) => run.deliveryStatus === "delivered");
  const recentDelivered = recentDeliveries.filter((run) => run.deliveryStatus === "delivered");
  const recentDeliveryRate =
    recentDeliveries.length > 0
      ? `${Math.round((recentDelivered.length / recentDeliveries.length) * 100)}%`
      : t("common.na");
  const dogfoodingTraffic = `${props.presenceCount} active / ${props.sessionsCount ?? t("common.na")} sessions`;
  const activeSessions24h = props.sessionRows.filter(
    (session) =>
      typeof session.updatedAt === "number" && nowMs - session.updatedAt <= 24 * 60 * 60 * 1000,
  );
  const cronSessions24h = activeSessions24h.filter((session) => session.key.includes("cron:"));
  const humanSessions24h = activeSessions24h.filter((session) => !session.key.includes("cron:"));
  const cronSuccess24hPct =
    runs24h.length > 0 ? Math.round((successfulRuns24h.length / runs24h.length) * 100) : null;
  const deliverySuccess24hPct =
    deliveries24h.length > 0
      ? Math.round((delivered24h.length / deliveries24h.length) * 100)
      : null;
  const discordProbeFresh =
    typeof discord?.lastProbeAt === "number" && nowMs - discord.lastProbeAt <= 20 * 60 * 1000;
  const opsGuardrails = [
    {
      metric: "Cron success (24h)",
      target: ">=95%",
      current: cronSuccess24hPct == null ? t("common.na") : `${cronSuccess24hPct}%`,
      status:
        cronSuccess24hPct == null
          ? "warn"
          : cronSuccess24hPct >= 95
            ? "ok"
            : cronSuccess24hPct >= 85
              ? "warn"
              : "danger",
    },
    {
      metric: "Delivery success (24h)",
      target: ">=98%",
      current: deliverySuccess24hPct == null ? t("common.na") : `${deliverySuccess24hPct}%`,
      status:
        deliverySuccess24hPct == null
          ? "warn"
          : deliverySuccess24hPct >= 98
            ? "ok"
            : deliverySuccess24hPct >= 90
              ? "warn"
              : "danger",
    },
    {
      metric: "Discord probe freshness",
      target: "<=20m",
      current: discord?.lastProbeAt ? formatRelativeTimestamp(discord.lastProbeAt) : t("common.na"),
      status: discord?.configured ? (discordProbeFresh ? "ok" : "warn") : "warn",
    },
    {
      metric: "Dogfooding human sessions (24h)",
      target: ">=5",
      current: `${humanSessions24h.length}`,
      status:
        humanSessions24h.length >= 5 ? "ok" : humanSessions24h.length >= 2 ? "warn" : "danger",
    },
  ] as const;
  const priorityAlerts: string[] = [];
  if (!props.connected) {
    priorityAlerts.push("Gateway is offline.");
  }
  if (props.cronEnabled === false) {
    priorityAlerts.push("Cron is disabled.");
  }
  if (enabledCronJobs.length === 0) {
    priorityAlerts.push("No enabled cron jobs are configured.");
  }
  if (deliverySuccess24hPct != null && deliverySuccess24hPct < 90) {
    priorityAlerts.push("Delivery success is below 90% over the last 24h.");
  }
  if (timeoutRiskLabel === "High") {
    priorityAlerts.push("Timeout risk is high; raise timeout seconds for long-running jobs.");
  }
  if (discord?.configured && !discord.running) {
    priorityAlerts.push("Discord is configured but not running.");
  }
  const pendingApprovals = props.execApprovalQueue?.length ?? 0;
  if (pendingApprovals > 0) {
    priorityAlerts.push(`${pendingApprovals} pending exec approval(s) — resolve in Nodes.`);
  }
  const tileToneForReliability =
    cronReliabilityPct == null ? "warn" : cronReliabilityPct >= 90 ? "ok" : "warn";
  const tileToneForTimeout = timeoutRiskLabel === "Low" ? "ok" : "warn";
  const tileToneForDiscord = discordDeliveryLabel === "Active" ? "ok" : "warn";

  const recentRunsList = props.cronRuns.slice(0, 5);

  return html`
    <section class="grid grid-cols-2">
      ${
        pendingApprovals > 0
          ? html`
              <div class="card callout warn" style="grid-column: 1 / -1;">
                <strong>Pending exec approvals: ${pendingApprovals}</strong>
                <p class="muted" style="margin-top: 6px;">
                  Resolve in the Nodes tab (exec approval queue).
                </p>
                <button
                  class="btn primary"
                  style="margin-top: 10px;"
                  type="button"
                  @click=${() => props.onNavigateToNodes?.()}
                >
                  Open Nodes
                </button>
              </div>
            `
          : ""
      }
      <div class="card">
        <div class="card-title">${t("overview.access.title")}</div>
        <div class="card-sub">${t("overview.access.subtitle")}</div>
        <div class="form-grid" style="margin-top: 16px;">
          <label class="field">
            <span>${t("overview.access.wsUrl")}</span>
            <input
              .value=${props.settings.gatewayUrl}
              @input=${(e: Event) => {
                const v = (e.target as HTMLInputElement).value;
                props.onSettingsChange({ ...props.settings, gatewayUrl: v });
              }}
              placeholder="ws://100.x.y.z:18789"
            />
          </label>
          ${
            isTrustedProxy
              ? ""
              : html`
                <label class="field">
                  <span>${t("overview.access.token")}</span>
                  <input
                    .value=${props.settings.token}
                    @input=${(e: Event) => {
                      const v = (e.target as HTMLInputElement).value;
                      props.onSettingsChange({ ...props.settings, token: v });
                    }}
                    placeholder="OPENCLAW_GATEWAY_TOKEN"
                  />
                </label>
                <label class="field">
                  <span>${t("overview.access.password")}</span>
                  <input
                    type="password"
                    .value=${props.password}
                    @input=${(e: Event) => {
                      const v = (e.target as HTMLInputElement).value;
                      props.onPasswordChange(v);
                    }}
                    placeholder="system or shared password"
                  />
                </label>
              `
          }
          <label class="field">
            <span>${t("overview.access.sessionKey")}</span>
            <input
              .value=${props.settings.sessionKey}
              @input=${(e: Event) => {
                const v = (e.target as HTMLInputElement).value;
                props.onSessionKeyChange(v);
              }}
            />
          </label>
          <label class="field">
            <span>${t("overview.access.language")}</span>
            <select
              .value=${currentLocale}
              @change=${(e: Event) => {
                const v = (e.target as HTMLSelectElement).value as Locale;
                void i18n.setLocale(v);
                props.onSettingsChange({ ...props.settings, locale: v });
              }}
            >
              ${SUPPORTED_LOCALES.map((loc) => {
                const key = loc.replace(/-([a-zA-Z])/g, (_, c) => c.toUpperCase());
                return html`<option value=${loc}>${t(`languages.${key}`)}</option>`;
              })}
            </select>
          </label>
        </div>
        <div class="row" style="margin-top: 14px;">
          <button class="btn" @click=${() => props.onConnect()}>${t("common.connect")}</button>
          <button class="btn" @click=${() => props.onRefresh()}>${t("common.refresh")}</button>
          <span class="muted">${
            isTrustedProxy ? t("overview.access.trustedProxy") : t("overview.access.connectHint")
          }</span>
        </div>
      </div>

      <div class="card">
        <div class="card-title">${t("overview.snapshot.title")}</div>
        <div class="card-sub">${t("overview.snapshot.subtitle")}</div>
        <div class="stat-grid" style="margin-top: 16px;">
          <div class="stat">
            <div class="stat-label">${t("overview.snapshot.status")}</div>
            <div class="stat-value ${props.connected ? "ok" : "warn"}">
              ${props.connected ? t("common.ok") : t("common.offline")}
            </div>
          </div>
          <div class="stat">
            <div class="stat-label">${t("overview.snapshot.uptime")}</div>
            <div class="stat-value">${uptime}</div>
          </div>
          <div class="stat">
            <div class="stat-label">${t("overview.snapshot.tickInterval")}</div>
            <div class="stat-value">${tick}</div>
          </div>
          <div class="stat">
            <div class="stat-label">${t("overview.snapshot.lastChannelsRefresh")}</div>
            <div class="stat-value">
              ${props.lastChannelsRefresh ? formatRelativeTimestamp(props.lastChannelsRefresh) : t("common.na")}
            </div>
          </div>
        </div>
        ${
          props.lastError
            ? html`<div class="callout danger" style="margin-top: 14px;">
              <div>${props.lastError}</div>
              ${pairingHint ?? ""}
              ${authHint ?? ""}
              ${insecureContextHint ?? ""}
            </div>`
            : html`
                <div class="callout" style="margin-top: 14px">
                  ${t("overview.snapshot.channelsHint")}
                </div>
              `
        }
      </div>
    </section>

    <section class="grid" style="grid-template-columns: repeat(4, minmax(0, 1fr)); margin-top: 18px;">
      <div class="card stat-card">
        <div class="stat-label">Gateway health</div>
        <div class="stat-value ${props.connected && !props.lastError ? "ok" : "warn"}">
          ${props.connected ? (props.lastError ? "Degraded" : "Healthy") : "Offline"}
        </div>
        <div class="muted">${props.lastError ? props.lastError : "No active gateway errors."}</div>
      </div>
      <div class="card stat-card">
        <div class="stat-label">Cron reliability</div>
        <div class="stat-value ${tileToneForReliability}">
          ${
            cronReliabilityPct == null
              ? t("common.na")
              : `${cronReliabilityPct}% (${reliableCronJobs.length}/${enabledCronJobs.length})`
          }
        </div>
        <div class="muted">${t("overview.stats.cronNext", { time: formatNextRun(props.cronNext) })}</div>
      </div>
      <div class="card stat-card">
        <div class="stat-label">Timeout risk</div>
        <div class="stat-value ${tileToneForTimeout}">${timeoutRiskLabel}</div>
        <div class="muted">
          ${timeoutErrorCount} timeout-like failures, ${timeoutRiskFromJobs} jobs need safer limits.
        </div>
      </div>
      <div class="card stat-card">
        <div class="stat-label">Discord delivery</div>
        <div class="stat-value ${tileToneForDiscord}">${discordDeliveryLabel}</div>
        <div class="muted">
          Last outbound: ${latestDiscordOutboundAt ? formatRelativeTimestamp(latestDiscordOutboundAt) : t("common.na")}
        </div>
      </div>
    </section>

    ${
      priorityAlerts.length > 0
        ? html`<section class="card" style="margin-top: 18px;">
            <div class="card-title">Priority alerts</div>
            <div class="card-sub">Address these first to stabilize delivery.</div>
            <div class="note-grid" style="margin-top: 12px;">
              ${priorityAlerts.map(
                (alert) =>
                  html`<div class="callout danger"><strong>Action:</strong> ${alert}</div>`,
              )}
            </div>
          </section>`
        : html`
            <section class="card" style="margin-top: 18px">
              <div class="card-title">Priority alerts</div>
              <div class="callout" style="margin-top: 12px">No critical alerts right now.</div>
            </section>
          `
    }

    ${
      recentRunsList.length > 0
        ? html`
            <section class="card" style="margin-top: 18px;">
              <div class="card-title">Recent runs</div>
              <div class="card-sub">Latest cron runs. <button class="btn link" type="button" @click=${() => props.onNavigateToCron?.()}>Open Cron tab</button></div>
              <div class="table" style="margin-top: 12px;">
                <div class="table-head">
                  <div>Job</div>
                  <div>Status</div>
                  <div>Time</div>
                </div>
                ${recentRunsList.map(
                  (run) => html`
                    <div class="table-row">
                      <div class="mono">${run.jobId ?? run.jobName ?? "—"}</div>
                      <div>
                        <span class="chip ${run.status === "ok" ? "chip-ok" : "chip-danger"}">
                          ${run.status ?? "—"}
                        </span>
                      </div>
                      <div class="muted">${formatRelativeTimestamp(run.ts)}</div>
                    </div>
                  `,
                )}
              </div>
            </section>
          `
        : ""
    }

    <section class="card" style="margin-top: 18px;">
      <div class="card-title">Cron reliability table</div>
      <div class="card-sub">Per-job status, latest delivery signal, next run, and most recent error.</div>
      <div class="table" style="margin-top: 12px;">
        <div class="table-head">
          <div>Job</div>
          <div>Status</div>
          <div>Delivery</div>
          <div>Next run</div>
          <div>Error</div>
        </div>
        ${
          props.cronJobs.length === 0
            ? html`
                <div class="muted">No cron jobs found.</div>
              `
            : props.cronJobs.map((job) => {
                const latestRun = latestRunByJob.get(job.id);
                const statusLabel = !job.enabled
                  ? "disabled"
                  : (job.state?.lastStatus ?? latestRun?.status ?? "unknown");
                const statusClass =
                  statusLabel === "ok"
                    ? "chip-ok"
                    : statusLabel === "error"
                      ? "chip-danger"
                      : "chip-warn";
                const deliveryLabel =
                  latestRun?.deliveryStatus ??
                  (job.delivery?.mode === "none" || !job.delivery ? "not-requested" : "unknown");
                const errorMessage =
                  job.state?.lastError ?? latestRun?.error ?? latestRun?.deliveryError ?? "";
                return html`
                  <div class="table-row">
                    <div class="mono">${job.name || job.id}</div>
                    <div><span class="chip ${statusClass}">${statusLabel}</span></div>
                    <div>${deliveryLabel}</div>
                    <div>${formatNextRun(job.state?.nextRunAtMs ?? null)}</div>
                    <div class="muted">${errorMessage || "—"}</div>
                  </div>
                `;
              })
        }
      </div>
    </section>

    <section class="card" style="margin-top: 18px;">
      <div class="card-title">Live delivery + dogfooding KPIs</div>
      <div class="card-sub">Rolling 60-minute delivery outcomes plus operator usage signals.</div>
      <div class="grid grid-cols-3" style="margin-top: 14px;">
        <div class="stat">
          <div class="stat-label">Delivery success (60m)</div>
          <div class="stat-value">${recentDeliveryRate}</div>
          <div class="muted">${recentDelivered.length}/${recentDeliveries.length || 0} delivered</div>
        </div>
        <div class="stat">
          <div class="stat-label">Runs observed (60m)</div>
          <div class="stat-value">${recentRuns.length}</div>
          <div class="muted">Across ${enabledCronJobs.length} enabled jobs</div>
        </div>
        <div class="stat">
          <div class="stat-label">Dogfooding traffic</div>
          <div class="stat-value">${props.presenceCount}</div>
          <div class="muted">${dogfoodingTraffic}</div>
        </div>
      </div>
      <div class="table" style="margin-top: 14px;">
        <div class="table-head">
          <div>Guardrail</div>
          <div>Target</div>
          <div>Current</div>
          <div>Status</div>
        </div>
        ${opsGuardrails.map(
          (entry) => html`
            <div class="table-row">
              <div>${entry.metric}</div>
              <div class="mono">${entry.target}</div>
              <div>${entry.current}</div>
              <div>
                <span class="chip ${entry.status === "ok" ? "chip-ok" : entry.status === "danger" ? "chip-danger" : "chip-warn"}">
                  ${entry.status}
                </span>
              </div>
            </div>
          `,
        )}
      </div>
      <div class="muted" style="margin-top: 12px;">
        Dogfooding split (24h): ${humanSessions24h.length} human sessions, ${cronSessions24h.length} cron sessions.
      </div>
    </section>

    <section class="grid grid-cols-3" style="margin-top: 18px;">
      <div class="card stat-card">
        <div class="stat-label">${t("overview.stats.instances")}</div>
        <div class="stat-value">${props.presenceCount}</div>
        <div class="muted">${t("overview.stats.instancesHint")}</div>
      </div>
      <div class="card stat-card">
        <div class="stat-label">${t("overview.stats.sessions")}</div>
        <div class="stat-value">${props.sessionsCount ?? t("common.na")}</div>
        <div class="muted">${t("overview.stats.sessionsHint")}</div>
      </div>
      <div class="card stat-card">
        <div class="stat-label">${t("overview.stats.cron")}</div>
        <div class="stat-value">
          ${props.cronEnabled == null ? t("common.na") : props.cronEnabled ? t("common.enabled") : t("common.disabled")}
        </div>
        <div class="muted">${t("overview.stats.cronNext", { time: formatNextRun(props.cronNext) })}</div>
      </div>
    </section>

    <section class="card" style="margin-top: 18px;">
      <div class="card-title">${t("overview.notes.title")}</div>
      <div class="card-sub">${t("overview.notes.subtitle")}</div>
      <div class="note-grid" style="margin-top: 14px;">
        <div>
          <div class="note-title">${t("overview.notes.tailscaleTitle")}</div>
          <div class="muted">
            ${t("overview.notes.tailscaleText")}
          </div>
        </div>
        <div>
          <div class="note-title">${t("overview.notes.sessionTitle")}</div>
          <div class="muted">${t("overview.notes.sessionText")}</div>
        </div>
        <div>
          <div class="note-title">${t("overview.notes.cronTitle")}</div>
          <div class="muted">${t("overview.notes.cronText")}</div>
        </div>
      </div>
    </section>
  `;
}
