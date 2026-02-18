import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="flash-toast-bridge" and dispatches flash payloads to the custom toast system.
export default class extends Controller {
  static targets = ["message"];

  connect() {
    this.flushPendingMessages();
  }

  messageTargetConnected(element) {
    this.dispatchMessage(element);
  }

  flushPendingMessages() {
    this.messageTargets.forEach((element) => this.dispatchMessage(element));
  }

  dispatchMessage(element) {
    if (!element || element.dataset.dispatched === "true") return;

    const message = element.textContent?.trim();
    if (!message && element.dataset.htmlSafe !== "true") {
      element.remove();
      return;
    }

    const type = element.dataset.toastType || "default";
    const htmlSafe = element.dataset.htmlSafe === "true";
    const detail = {
      type: type,
      description: "",
    };

    if (htmlSafe) {
      detail.html = element.innerHTML;
      detail.message = message || "Notification";
    } else {
      detail.message = message;
      detail.html = "";
    }

    if (typeof window.toast === "function") {
      window.toast(detail.message, detail);
    } else {
      if (!Array.isArray(window.__pendingToasts)) {
        window.__pendingToasts = [];
      }
      window.__pendingToasts.push(detail);
    }

    element.dataset.dispatched = "true";
    element.remove();
  }
}
