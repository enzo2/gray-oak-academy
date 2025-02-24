import { Controller } from "@hotwired/stimulus"

// Scrolls to the last message on initial load 
export default class extends Controller {
  static targets = ["messages"]

  connect() {
    //console.log("scrollToBottom")
    this.scrollToBottom()
    //this.setupMutationObserver()
  }

  scrollToBottom() {
    if (this.messagesTarget.lastElementChild) {
      this.messagesTarget.lastElementChild.scrollIntoView({ behavior: 'smooth' })
      //console.log("scrollIntoView")
    }
  }

  // Don't need this unless you want to scroll to bottom on every message
  /*
  setupMutationObserver() {
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
          mutation.addedNodes.forEach((node, index) => {
            console.log(`Added node ${index}:`, node);
            // Trigger scrollToBottom for any added node
            //this.scrollToBottom();
            //console.log("scrollToBottom")
          });
        }
      });
    })

    observer.observe(this.messagesTarget, {
      childList: true,
      subtree: true
    })
  }
  */

}
