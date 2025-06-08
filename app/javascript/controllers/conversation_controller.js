import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages", "userMessage", "assistantMessage", "assistantMessageContent"];

  connect() {
    // Scroll to bottom upon initialization
    this.scrollToBottom();
  }

  scrollToBottom() {
    if (this.messagesTarget.lastElementChild) {
      this.messagesTarget.lastElementChild.scrollIntoView({ behavior: 'smooth' });
    }
  }

  renderKatexInMessages() {
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

  // Setup for new user messages
  userMessageTargetConnected(element) {
    this.scrollToBottom();
  }

  // Setup for new assistant messages
  assistantMessageTargetConnected(element) {
    this.scrollToBottom();
  }

  // Render KaTeX initially and upon new messages
  assistantMessageContentTargetConnected(element) {
    this.renderKatexInMessages();
  }

  disconnect() {
  }
}