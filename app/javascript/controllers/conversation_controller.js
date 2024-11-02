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
    const observer = new MutationObserver((mutations) => {
      for (let mutation of mutations) {
        if (mutation.type === 'childList') {
          // Check if the added node is a message
          const addedNodes = Array.from(mutation.addedNodes);
          const isNewMessage = addedNodes.some(node => 
            node.nodeType === Node.ELEMENT_NODE && 
            node.id && 
            node.id.endsWith('_messages')
          );

          if (isNewMessage) {
            this.scrollToBottom()
            break;
          }
        }
      }
    })

    observer.observe(this.messagesTarget, {
      childList: true,
      subtree: true
    })
  }
}
