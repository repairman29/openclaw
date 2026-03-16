import { html, nothing } from "lit";
import { unsafeHTML } from "lit/directives/unsafe-html.js";
import type { ToolStreamEntry } from "../app-tool-stream.ts";
import { icons } from "../icons.ts";
import { toSanitizedMarkdownHtml } from "../markdown.ts";
import { formatToolDetail, resolveToolDisplay } from "../tool-display.ts";

export type SidecarMode = "tool" | "artifacts" | "timeline";

export type SidecarProps = {
  mode: SidecarMode;
  toolContent: string | null;
  toolError: string | null;
  pinnedArtifacts: Array<{ id: string; title: string; content: string }>;
  runTimelineEntries: ToolStreamEntry[];
  onClose: () => void;
  onModeChange: (mode: SidecarMode) => void;
  onViewRawText: () => void;
  onOpenToolOutput: (content: string) => void;
  onUnpinArtifact: (id: string) => void;
};

function formatDurationMs(ms: number): string {
  if (ms < 1000) {
    return `${ms}ms`;
  }
  return `${(ms / 1000).toFixed(1)}s`;
}

export function renderSidecar(props: SidecarProps) {
  const { mode, toolContent, toolError, pinnedArtifacts, runTimelineEntries } = props;

  const renderToolPanel = () => {
    if (toolError) {
      return html`
        <div class="callout danger">${toolError}</div>
        <button @click=${props.onViewRawText} class="btn" style="margin-top: 12px;">
          View Raw Text
        </button>
      `;
    }
    if (toolContent) {
      return html`
        <div class="sidebar-markdown">${unsafeHTML(toSanitizedMarkdownHtml(toolContent))}</div>
      `;
    }
    return html`
      <div class="muted">No content. Click a tool card in the thread to view output.</div>
    `;
  };

  const renderArtifactsPanel = () => {
    if (pinnedArtifacts.length === 0) {
      return html`
        <div class="muted">No pinned artifacts. Use “Pin to sidecar” on a message to keep it here.</div>
      `;
    }
    return html`
      <div class="sidebar-artifacts-list">
        ${pinnedArtifacts.map(
          (art) => html`
            <div class="sidebar-artifact-item">
              <div class="sidebar-artifact-title" title=${art.title}>${art.title}</div>
              <button
                class="btn sidebar-artifact-unpin"
                type="button"
                aria-label="Unpin"
                title="Unpin from sidecar"
                @click=${() => props.onUnpinArtifact(art.id)}
              >
                ${icons.x}
              </button>
            </div>
            <div class="sidebar-markdown sidebar-artifact-content">${unsafeHTML(toSanitizedMarkdownHtml(art.content))}</div>
          </div>
        `,
        )}
      </div>
    `;
  };

  const renderTimelinePanel = () => {
    if (runTimelineEntries.length === 0) {
      return html`
        <div class="muted">No tool calls in this run. Timeline appears when the agent uses tools.</div>
      `;
    }
    return html`
      <div class="sidebar-timeline">
        ${runTimelineEntries.map((entry, i) => {
          const display = resolveToolDisplay({ name: entry.name, args: entry.args });
          const detail = formatToolDetail(display);
          const durationMs = entry.output != null ? entry.updatedAt - entry.startedAt : null;
          return html`
            <div class="sidebar-timeline-entry">
              <div class="sidebar-timeline-index">${i + 1}</div>
              <div class="sidebar-timeline-body">
                <div class="sidebar-timeline-name">${display.label}</div>
                ${detail ? html`<div class="sidebar-timeline-detail mono">${detail}</div>` : nothing}
                <div class="sidebar-timeline-meta">
                  ${
                    durationMs != null
                      ? html`<span>${formatDurationMs(durationMs)}</span>`
                      : html`
                          <span class="muted">running…</span>
                        `
                  }
                </div>
                ${
                  entry.output != null && entry.output.length > 0
                    ? html`
                      <button
                        class="btn btn--small"
                        type="button"
                        @click=${() => props.onOpenToolOutput(entry.output!)}
                      >
                        View output
                      </button>
                    `
                    : nothing
                }
              </div>
            </div>
          `;
        })}
      </div>
    `;
  };

  const content =
    mode === "tool"
      ? renderToolPanel()
      : mode === "artifacts"
        ? renderArtifactsPanel()
        : renderTimelinePanel();

  const tabs: { mode: SidecarMode; label: string }[] = [
    { mode: "tool", label: "Tool output" },
    { mode: "artifacts", label: `Artifacts (${pinnedArtifacts.length})` },
    { mode: "timeline", label: "Run timeline" },
  ];

  return html`
    <div class="sidebar-panel sidebar-panel--with-tabs">
      <div class="sidebar-header">
        <div class="sidebar-tabs">
          ${tabs.map(
            (t) => html`
              <button
                class="btn sidebar-tab ${mode === t.mode ? "sidebar-tab--active" : ""}"
                type="button"
                @click=${() => props.onModeChange(t.mode)}
              >
                ${t.label}
              </button>
            `,
          )}
        </div>
        <button @click=${props.onClose} class="btn" title="Close sidebar">${icons.x}</button>
      </div>
      <div class="sidebar-content">${content}</div>
    </div>
  `;
}
