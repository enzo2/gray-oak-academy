import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages"]

  connect() {
    this.scrollToBottom()
    this.setupMutationObserver()
  }

  scrollToBottom() {
    if (this.messagesTarget.lastElementChild) {
      this.messagesTarget.lastElementChild.scrollIntoView({ behavior: 'smooth' })
    }
  }

  setupMutationObserver() {
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
          mutation.addedNodes.forEach((node, index) => {
            //console.log(`Added node ${index}:`, node);
            // Trigger scrollToBottom for any added node
            this.scrollToBottom();
          });
        }
      });
    })

    observer.observe(this.messagesTarget, {
      childList: true,
      subtree: true
    })
  }

}
