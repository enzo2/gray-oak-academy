// Bridges results reported by a sandboxed applet iframe back to the app.
//
// Applet iframes are sandboxed WITHOUT `allow-same-origin`, so messages from
// them arrive with an opaque ("null") origin. We therefore authenticate a
// message by matching `event.source` to the specific iframe's contentWindow,
// not by origin. The reported payload is untrusted data: it is size-capped and
// only ever handled as JSON/text (never eval'd or inserted as HTML).
//
// Inside the applet, `window.GOA.report(data, { send })` (injected by the iframe
// shell) reports a result; this helper re-broadcasts it as an `applet:result`
// window CustomEvent. The compose controller buffers results as a pending
// attachment and delivers them with the student's next message (or auto-sends
// when `send` is true).

const MAX_PAYLOAD_BYTES = 16 * 1024;

export function attachAppletResultChannel(iframe, meta = {}) {
  const handler = (event) => {
    if (event.source !== iframe.contentWindow) return;
    const data = event.data;
    if (!data || data.source !== "goa-applet" || data.v !== 1) return;

    // Untrusted payload: enforce a size cap before doing anything with it.
    try {
      if (JSON.stringify(data.data ?? null).length > MAX_PAYLOAD_BYTES) {
        console.warn("[applet-result] payload too large, ignoring");
        return;
      }
    } catch (_e) {
      return; // non-serializable payload
    }

    window.dispatchEvent(new CustomEvent("applet:result", {
      detail: {
        conversationId: meta.conversationId || null,
        messageId: meta.messageId || null,
        appletKey: meta.appletKey || null,
        title: meta.title || null,
        type: data.type || "result",
        name: typeof data.name === "string" ? data.name.slice(0, 200) : null,
        send: data.send === true,
        data: data.data ?? null
      }
    }));
  };

  window.addEventListener("message", handler);
  return function detach() {
    window.removeEventListener("message", handler);
  };
}
