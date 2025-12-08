import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["indicator", "tooltip"]
  static classes = ["connected", "disconnected"]
  static values = {
    connectedIcon: { type: String, default: "cloud-check" },
    disconnectedIcon: { type: String, default: "cloud-slash" }
  }

  connect() {
    this.boundHandleConnected = this.handleConnected.bind(this)
    this.boundHandleDisconnected = this.handleDisconnected.bind(this)
    this.boundHandleOnline = this.handleOnline.bind(this)
    this.boundHandleOffline = this.handleOffline.bind(this)
    this.streamAttributeObservers = []
    this.everConnected = false

    document.addEventListener("turbo:stream-connected", this.boundHandleConnected)
    document.addEventListener("turbo:stream-disconnected", this.boundHandleDisconnected)
    window.addEventListener("online", this.boundHandleOnline)
    window.addEventListener("offline", this.boundHandleOffline)

    this.observeStreamSources()

    // Initial check
    if (!navigator.onLine) {
      this.setDisconnected()
    }
  }

  disconnect() {
    document.removeEventListener("turbo:stream-connected", this.boundHandleConnected)
    document.removeEventListener("turbo:stream-disconnected", this.boundHandleDisconnected)
    window.removeEventListener("online", this.boundHandleOnline)
    window.removeEventListener("offline", this.boundHandleOffline)
    this.streamAttributeObservers.forEach((observer) => observer.disconnect())
    this.streamAttributeObservers = []
  }

  handleConnected(event) {
    this.everConnected = true
    this.setConnected()
  }

  handleDisconnected(event) {
    if (!this.everConnected) return
    this.setDisconnected()
  }

  handleOnline() {
    // Wait for stream to connect
  }

  handleOffline() {
    this.setDisconnected()
  }

  setConnected() {
    this.indicatorTarget.classList.remove(...this.disconnectedClasses)
    this.indicatorTarget.classList.add(...this.connectedClasses)
    this.indicatorTarget.setAttribute("name", this.connectedIconValue)
    if (this.hasTooltipTarget) {
      this.tooltipTarget.setAttribute("data-tooltip-content", "Connected")
    }
  }

  setDisconnected() {
    this.indicatorTarget.classList.remove(...this.connectedClasses)
    this.indicatorTarget.classList.add(...this.disconnectedClasses)
    this.indicatorTarget.setAttribute("name", this.disconnectedIconValue)
    if (this.hasTooltipTarget) {
      this.tooltipTarget.setAttribute("data-tooltip-content", "Disconnected")
    }
  }

  observeStreamSources() {
    const sources = document.querySelectorAll("turbo-cable-stream-source")
    sources.forEach((source) => {
      const observer = new MutationObserver((mutations) => {
        if (!mutations.some((mutation) => mutation.type === "attributes" && mutation.attributeName === "connected")) {
          return
        }

        const connected = source.hasAttribute("connected")
        if (connected) {
          this.everConnected = true
          this.setConnected()
        } else if (this.everConnected) {
          this.setDisconnected()
        }
      })

      observer.observe(source, { attributes: true, attributeFilter: ["connected"] })
      this.streamAttributeObservers.push(observer)
    })
  }
}
