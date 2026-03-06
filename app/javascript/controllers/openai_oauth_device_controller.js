import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    pollUrl: String,
    intervalMs: Number,
    settingsUrl: String
  }

  static targets = ["status", "error"]

  connect() {
    this.isPolling = false
    this.waitingForUser = true
    this.setStatus("Enter the code on OpenAI's page, then click \"I've Entered The Code\".")
  }

  disconnect() {
    this.clearTimer()
  }

  pollNow() {
    this.waitingForUser = false
    this.clearTimer()
    this.poll()
  }

  async poll() {
    if (this.isPolling) return
    this.isPolling = true
    this.setError("")
    this.setStatus("Checking OpenAI authorization...")

    try {
      const response = await fetch(this.pollUrlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        credentials: "same-origin"
      })
      const data = await response.json()

      if (data.status === "connected" && data.redirect_url) {
        window.location.href = data.redirect_url
        return
      }

      if (data.status === "pending") {
        this.setStatus("Waiting for OpenAI authorization...")
        this.schedulePoll((data.interval_seconds || (this.intervalMsValue / 1000) || 5) * 1000)
        return
      }

      this.setStatus("")
      this.setError(data.message || "OpenAI authorization failed.")
      if (data.status === "expired" || data.status === "denied") {
        this.scheduleRedirect()
      }
    } catch (_error) {
      this.setStatus("")
      this.setError("Unable to check OpenAI authorization. Please try again.")
      if (!this.waitingForUser) {
        this.schedulePoll(this.intervalMsValue || 5000)
      }
    } finally {
      this.isPolling = false
    }
  }

  schedulePoll(delayMs) {
    this.clearTimer()
    this.timer = setTimeout(() => this.poll(), delayMs)
  }

  scheduleRedirect() {
    this.clearTimer()
    this.timer = setTimeout(() => {
      window.location.href = this.settingsUrlValue
    }, 2500)
  }

  clearTimer() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = null
    }
  }

  setStatus(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  setError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.classList.toggle("hidden", !message)
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
