import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "accent", "accentIcon", "accentText", "userMessage", "assistantMessage", "assistantMessageContent"];
  static values = { welcomeMessages: Array };

  connect() {
    // Debounced KaTeX rendering function
    this.debouncedRenderKatex = this.debounce(this.renderKatexInMessages.bind(this), 200);

    // Listen for Turbo Stream updates to re-render KaTeX
    document.addEventListener("turbo:after-stream-render", this.debouncedRenderKatex);

    // Watch for placeholder (#new_message) being added/removed via Turbo Streams
    this.messagesObserver = new MutationObserver(() => this.updateAccentState());
    if (this.hasMessagesTarget) {
      this.messagesObserver.observe(this.messagesTarget, { childList: true });
    }

    this.updateAccentState();
  }

  disconnect() {
    document.removeEventListener("turbo:after-stream-render", this.debouncedRenderKatex);
    if (this.messagesObserver) this.messagesObserver.disconnect();
  }

  // Debounce utility
  debounce(func, wait) {
    let timeout;
    return function(...args) {
      clearTimeout(timeout);
      timeout = setTimeout(() => func.apply(this, args), wait);
    };
  }

  updateAccentState() {
    if (!this.hasAccentTarget) return;

    const hasMessages = this.messagesTarget.querySelector("[data-message-id-param]") != null;
    const hasPlaceholder = !!this.messagesTarget.querySelector("#new_message");

    if (hasPlaceholder) {
      this.setThinkingState();
    } else if (!hasMessages) {
      this.setWelcomeState();
    } else {
      this.setIdleState();
    }
  }

  setWelcomeState() {
    if (!this.hasAccentTextTarget || !this.hasAccentIconTarget) return;
    // Only pick a new message if we're not already showing one
    if (!this.welcomeMessage) {
      const welcomeMessages = this.hasWelcomeMessagesValue ? this.welcomeMessagesValue : [];
      this.welcomeMessage = welcomeMessages.length > 0 ? welcomeMessages[Math.floor(Math.random() * welcomeMessages.length)] : "";
    }
    this.accentTextTarget.textContent = this.welcomeMessage;
    this.accentIconTarget.classList.remove("animate-tree-breathe");
  }

  setThinkingState() {
    if (!this.hasAccentTextTarget || !this.hasAccentIconTarget) return;
    this.accentTextTarget.textContent = "Thinking\u2026";
    this.accentIconTarget.classList.add("animate-tree-breathe");
  }

  setIdleState() {
    if (!this.hasAccentTextTarget || !this.hasAccentIconTarget) return;
    this.accentTextTarget.textContent = "";
    this.accentIconTarget.classList.remove("animate-tree-breathe");
  }

  scrollToBottom() {
    //console.log("scrolling to bottom")
    const messageElements = this.messagesTarget.querySelectorAll("[data-message-id-param], #new_message");
    const lastMessage = messageElements[messageElements.length - 1];
    if (lastMessage) {
      lastMessage.scrollIntoView({ behavior: 'smooth', block: 'end' });
      return;
    }

    if (this.hasAccentTarget) {
      this.accentTarget.scrollIntoView({ behavior: 'smooth', block: 'end' });
    }
  }

  renderKatexInMessages() {
    // Skip if the text doesn't include $$, $, or \\[
    let text = this.messagesTarget.textContent
    if (!text.includes("$$") && !text.includes("$") && !text.includes("\\[")) {
      //console.log("No KaTeX to render");
      return;
    }
    //console.log("Rendering KaTeX in messages..")
    this.assistantMessageTargets.forEach(message => {
      renderMathInElement(message, {
        delimiters: [
          { left: "$$", right: "$$", display: true },
          { left: "$", right: "$", display: false },
          { left: "\\[", right: "\\]", display: true }
        ],
        throwOnError: false
      });
    });
  }

  // Scroll to new user messages
  userMessageTargetConnected(element) {
    this.scrollToBottom();
    this.updateAccentState();
  }
  
  assistantMessageTargetConnected(element) {
    // Scroll to new assistant messages
    this.scrollToBottom();
    // Render KaTeX on page load for existing messages 
    // (For new messages, will fire but irrelevant since have to run again after turbo:after-stream-render)
    this.renderKatexInMessages();
    this.updateAccentState();
  }
}
