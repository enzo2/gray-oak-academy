import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["methodSelect", "speechWrapper", "chatWrapper", "speechInput", "chatInput"]

  connect() {
    // Ensure targets exist before attempting to update UI
    if (!this.hasMethodSelectTarget) return
    // Initialize UI based on current selection
    this.update()
  }

  update(event) {
    // Allow update to be called from data-action or on connect
    const method = this.methodSelectTarget.value
    if (method === "speech") {
      this.showSpeech()
    } else if (method === "chat") {
      this.showChat()
    } else {
      this.showSpeech()
    }
  }

  showSpeech() {
    if (this.hasSpeechWrapperTarget) this.speechWrapperTarget.classList.remove("hidden")
    if (this.hasChatWrapperTarget) this.chatWrapperTarget.classList.add("hidden")
    if (this.hasSpeechInputTarget) this._enable(this.speechInputTarget)
    if (this.hasChatInputTarget) this._disable(this.chatInputTarget)
  }

  showChat() {
    if (this.hasSpeechWrapperTarget) this.speechWrapperTarget.classList.add("hidden")
    if (this.hasChatWrapperTarget) this.chatWrapperTarget.classList.remove("hidden")
    if (this.hasSpeechInputTarget) this._disable(this.speechInputTarget)
    if (this.hasChatInputTarget) this._enable(this.chatInputTarget)
  }

  // Helpers to (dis)able form inputs so only the visible input is submitted
  _disable(el) {
    try {
      el.disabled = true
      el.setAttribute("aria-hidden", "true")
    } catch (e) {
      // ignore if element not present
    }
  }

  _enable(el) {
    try {
      el.disabled = false
      el.removeAttribute("aria-hidden")
    } catch (e) {
      // ignore if element not present
    }
  }
}
