import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages"]

  connect() {
    //console.log("Conversation controller connected")
    this.scrollToBottom()
    this.setupMutationObserver()
  }

  scrollToBottom() {
    console.log("Scrolling to bottom")
    const messagesContainer = this.messagesTarget
    messagesContainer.scrollTop = messagesContainer.scrollHeight
  }

  setupMutationObserver() {
    //console.log("Setting up mutation observer")
    const observer = new MutationObserver((mutations) => {
      for (let mutation of mutations) {
        if (mutation.type === 'childList') {
          const addedNode = mutations[0].addedNodes[0];
          if (addedNode && addedNode.id && addedNode.id.endsWith('_messages')) {
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
