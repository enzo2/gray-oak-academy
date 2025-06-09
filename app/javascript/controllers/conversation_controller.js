import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "userMessage", "assistantMessage", "assistantMessageContent"];

  connect() {
    // Debounced KaTeX rendering function
    this.debouncedRenderKatex = this.debounce(this.renderKatexInMessages.bind(this), 200);

    // Listen for Turbo Stream updates to re-render KaTeX
    document.addEventListener("turbo:after-stream-render", this.debouncedRenderKatex);
  }

  disconnect() {
    document.removeEventListener("turbo:after-stream-render", this.debouncedRenderKatex);
  }

  // Debounce utility
  debounce(func, wait) {
    let timeout;
    return function(...args) {
      clearTimeout(timeout);
      timeout = setTimeout(() => func.apply(this, args), wait);
    };
  }
  
  scrollToBottom() {
    //console.log("scrolling to bottom")
    if (this.messagesTarget.lastElementChild) {
      this.messagesTarget.lastElementChild.scrollIntoView({ behavior: 'smooth', block: 'center' });
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
  }
  
  assistantMessageTargetConnected(element) {
    // Scroll to new assistant messages
    this.scrollToBottom();
    // Render KaTeX on page load for existing messages 
    // (For new messages, will fire but irrelevant since have to run again after turbo:after-stream-render)
    this.renderKatexInMessages();
  }

}