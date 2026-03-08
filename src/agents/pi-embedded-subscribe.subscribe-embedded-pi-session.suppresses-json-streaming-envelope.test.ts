import type { AssistantMessage } from "@mariozechner/pi-ai";
import { describe, expect, it, vi } from "vitest";
import {
  createSubscribedSessionHarness,
  emitAssistantTextDelta,
} from "./pi-embedded-subscribe.e2e-harness.js";

describe("subscribeEmbeddedPiSession", () => {
  it("suppresses structured JSON streaming and emits final plain text at message_end", () => {
    const onBlockReply = vi.fn();
    const onPartialReply = vi.fn();

    const { emit, subscription } = createSubscribedSessionHarness({
      runId: "run",
      onBlockReply,
      onPartialReply,
      blockReplyBreak: "message_end",
      blockReplyChunking: {
        minChars: 1,
        maxChars: 64,
        breakPreference: "paragraph",
      },
    });

    emit({ type: "message_start", message: { role: "assistant" } });
    emitAssistantTextDelta({ emit, delta: '{"type":"message",' });
    emitAssistantTextDelta({ emit, delta: '"content":"fix"}' });

    const assistantMessage = {
      role: "assistant",
      content: [{ type: "text", text: '{"type":"message","content":"fix"}' }],
    } as AssistantMessage;

    emit({ type: "message_end", message: assistantMessage });

    expect(onPartialReply).not.toHaveBeenCalled();
    expect(onBlockReply).toHaveBeenCalledTimes(1);
    expect(onBlockReply.mock.calls[0]?.[0]?.text).toBe("fix");
    expect(subscription.assistantTexts).toEqual(["fix"]);
  });
});
