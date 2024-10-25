import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages"]

  connect() {
    this.scrollToBottom()
    this.setupMutationObserver()
  }

  scrollToBottom() {
    const messagesContainer = this.messagesTarget
    messagesContainer.scrollTop = messagesContainer.scrollHeight
  }

  setupMutationObserver() {
    const observer = new MutationObserver(() => {
      this.scrollToBottom()
    })

    observer.observe(this.messagesTarget, {
      childList: true,
      subtree: true
    })
  }
}
