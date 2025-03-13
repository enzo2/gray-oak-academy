import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["user", "assistant", "messages"]

  connect() {
    //console.log("initial scrollToBottom")
    this.scrollToBottom()
  }

  scrollToBottom() {
    if (this.messagesTarget.lastElementChild) {
      this.messagesTarget.lastElementChild.scrollIntoView({ behavior: 'smooth' })
      //console.log("scrollIntoView")
    }
  }

  userTargetConnected(element) {
    //console.log("Message target connected:", element)
    this.scrollToBottom()
  }

  assistantTargetConnected(element) {
    //console.log("Message target connected:", element)
    this.scrollToBottom()
  }
}
