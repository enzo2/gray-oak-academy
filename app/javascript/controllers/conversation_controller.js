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

  renderKatexInMessages() {
    // Find all assistant message elements
    const assistantMessages = this.assistantTargets;
    
    assistantMessages.forEach(message => {
      renderMathInElement(message, {
        // Configure the delimiters that LLMs naturally use
        delimiters: [
            {left: "$$", right: "$$", display: true},
            {left: "$", right: "$", display: false},
            {left: "\\(", right: "\\)", display: false},
            {left: "\\begin{equation}", right: "\\end{equation}", display: true},
            {left: "\\begin{align}", right: "\\end{align}", display: true},
            {left: "\\begin{alignat}", right: "\\end{alignat}", display: true},
            {left: "\\begin{gather}", right: "\\end{gather}", display: true},
            {left: "\\begin{CD}", right: "\\end{CD}", display: true},
            {left: "\\[", right: "\\]", display: true}
        ],
        throwOnError: false
      });
    });
  }

  userTargetConnected(element) {
    //console.log("Message target connected:", element)
    this.scrollToBottom()
  }

  assistantTargetConnected(element) {
    //console.log("Message target connected:", element)
    this.scrollToBottom()
    this.renderKatexInMessages()
  }
}
