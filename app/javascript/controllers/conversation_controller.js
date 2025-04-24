import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "user", "assistant", "assistantContent"];

  connect() {
    this.scrollToBottom();
  }

  scrollToBottom() {
    if (this.messagesTarget.lastElementChild) {
      this.messagesTarget.lastElementChild.scrollIntoView({ behavior: 'smooth' });
    }
  }

  renderKatexInMessages() {
    this.assistantTargets.forEach(message => {
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

  userTargetConnected(element) {
    this.scrollToBottom();
  }

  assistantTargetConnected(element) {
    this.renderKatexInMessages();
    this.scrollToBottom();
  }

  assistantContentTargetConnected(element) {
    this.renderKatexInMessages();
  }

  disconnect() {
  }
}
