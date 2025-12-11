import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["indicator", "tooltip"]
  static classes = ["connected", "disconnected"]
  static values = {
    connectedIcon: { type: String, default: "cloud-check" },
    disconnectedIcon: { type: String, default: "cloud-slash" },
    reconnectDelay: { type: Number, default: 2000 },
    maxReconnectDelay: { type: Number, default: 30000 }
  }

  connect() {
    this.boundHandleConnected = this.handleConnected.bind(this)
    this.boundHandleDisconnected = this.handleDisconnected.bind(this)
    this.boundHandleOnline = this.handleOnline.bind(this)
    this.boundHandleOffline = this.handleOffline.bind(this)
    this.streamAttributeObservers = []
    this.everConnected = false
    this.reconnectAttempts = 0
    this.reconnectTimer = null

    document.addEventListener("turbo:stream-connected", this.boundHandleConnected)
    document.addEventListener("turbo:stream-disconnected", this.boundHandleDisconnected)
    window.addEventListener("online", this.boundHandleOnline)
    window.addEventListener("offline", this.boundHandleOffline)

    this.observeStreamSources()
    this.checkInitialState()
  }

  // Check if streams are already connected on page load
  checkInitialState() {
    if (!navigator.onLine) {
      this.setDisconnected()
      return
    }

    const sources = document.querySelectorAll("turbo-cable-stream-source")
    if (sources.length === 0) return

    // Check if any source is already connected
    const anyConnected = Array.from(sources).some(s => s.hasAttribute("connected"))
    if (anyConnected) {
      this.everConnected = true
      this.setConnected()
    }
  }

  disconnect() {
    document.removeEventListener("turbo:stream-connected", this.boundHandleConnected)
    document.removeEventListener("turbo:stream-disconnected", this.boundHandleDisconnected)
    window.removeEventListener("online", this.boundHandleOnline)
    window.removeEventListener("offline", this.boundHandleOffline)
    this.streamAttributeObservers.forEach((observer) => observer.disconnect())
    this.streamAttributeObservers = []
    if (this.domObserver) {
      this.domObserver.disconnect()
      this.domObserver = null
    }
    this.clearReconnectTimer()
    this.stopWebSocketMonitoring()
  }

  handleConnected() {
    this.everConnected = true
    this.reconnectAttempts = 0
    this.clearReconnectTimer()
    this.setConnected()
  }

  handleDisconnected() {
    if (!this.everConnected) return
    this.setDisconnected()
    this.scheduleReconnect()
  }

  handleOnline() {
    // Browser back online - check if already connected, otherwise attempt reconnect
    const sources = document.querySelectorAll("turbo-cable-stream-source")
    const anyConnected = Array.from(sources).some(s => s.hasAttribute("connected"))
    if (anyConnected) {
      this.setConnected()
    } else {
      this.attemptReconnect()
    }
  }

  handleOffline() {
    this.clearReconnectTimer()
    this.setDisconnected()
  }

  clearReconnectTimer() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
  }

  scheduleReconnect() {
    if (!navigator.onLine) return
    this.clearReconnectTimer()

    // Exponential backoff: 2s, 4s, 8s, 16s, max 30s
    const delay = Math.min(
      this.reconnectDelayValue * Math.pow(2, this.reconnectAttempts),
      this.maxReconnectDelayValue
    )

    this.reconnectTimer = setTimeout(() => {
      this.attemptReconnect()
    }, delay)
  }

  attemptReconnect() {
    if (!navigator.onLine) return

    this.reconnectAttempts++

    // Find all turbo-cable-stream-source elements that aren't connected
    const sources = document.querySelectorAll("turbo-cable-stream-source:not([connected])")

    if (sources.length === 0) {
      // All sources connected, nothing to do
      return
    }

    // Try to reconnect ActionCable first
    const cable = window.Turbo?.cable || this.getActionCable()
    if (cable?.connection) {
      // If WebSocket is closed, reopen it
      if (cable.connection.disconnected) {
        cable.connection.open()
      }
    }

    // Re-insert stream sources to force re-subscription
    sources.forEach((source) => {
      const parent = source.parentElement
      if (!parent) return

      const nextSibling = source.nextSibling
      // Clone attributes to preserve signed-stream-name
      const clone = source.cloneNode(true)
      parent.removeChild(source)

      // Small delay to ensure clean removal before re-adding
      setTimeout(() => {
        if (nextSibling && nextSibling.parentElement === parent) {
          parent.insertBefore(clone, nextSibling)
        } else {
          parent.appendChild(clone)
        }
      }, 100)
    })

    // Check again after a delay - if still disconnected, schedule another attempt
    setTimeout(() => {
      const stillDisconnected = document.querySelectorAll("turbo-cable-stream-source:not([connected])")
      if (stillDisconnected.length > 0 && this.everConnected) {
        this.scheduleReconnect()
      }
    }, 1000)
  }

  getActionCable() {
    // Try to get ActionCable consumer from various possible locations
    // First check turbo-cable-stream-source elements for their subscription's consumer
    const source = document.querySelector("turbo-cable-stream-source")
    if (source?.subscription?.consumer) {
      return source.subscription.consumer
    }
    // Fallback to global locations
    return window.ActionCable?.consumer ||
           window.App?.cable ||
           window.consumer
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
    // Observe existing stream sources
    this.observeExistingStreamSources()

    // Watch for new stream sources being added to the DOM
    this.domObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType === Node.ELEMENT_NODE) {
            if (node.tagName === "TURBO-CABLE-STREAM-SOURCE") {
              this.observeStreamSource(node)
            }
            // Also check children
            node.querySelectorAll?.("turbo-cable-stream-source").forEach((source) => {
              this.observeStreamSource(source)
            })
          }
        }
      }
    })
    this.domObserver.observe(document.body, { childList: true, subtree: true })

    // Also monitor ActionCable WebSocket state directly
    this.startWebSocketMonitoring()
  }

  observeExistingStreamSources() {
    const sources = document.querySelectorAll("turbo-cable-stream-source")
    sources.forEach((source) => this.observeStreamSource(source))
  }

  observeStreamSource(source) {
    // Don't double-observe
    if (source.__connectionStatusObserved) return
    source.__connectionStatusObserved = true

    // Check current state immediately
    if (source.hasAttribute("connected")) {
      this.everConnected = true
      this.reconnectAttempts = 0
      this.clearReconnectTimer()
      this.setConnected()
    }

    const observer = new MutationObserver((mutations) => {
      if (!mutations.some((mutation) => mutation.type === "attributes" && mutation.attributeName === "connected")) {
        return
      }

      const connected = source.hasAttribute("connected")
      if (connected) {
        this.everConnected = true
        this.reconnectAttempts = 0
        this.clearReconnectTimer()
        this.setConnected()
      } else if (this.everConnected) {
        this.setDisconnected()
        this.scheduleReconnect()
      }
    })

    observer.observe(source, { attributes: true, attributeFilter: ["connected"] })
    this.streamAttributeObservers.push(observer)
  }

  startWebSocketMonitoring() {
    // Poll ActionCable connection state as a fallback
    // The WebSocket can close without the stream source attribute changing immediately
    this.wsMonitorInterval = setInterval(() => {
      if (!this.everConnected) return

      const cable = window.Turbo?.cable || this.getActionCable()
      const ws = cable?.connection?.webSocket

      if (ws && ws.readyState === WebSocket.CLOSED) {
        // WebSocket is closed but we thought we were connected
        const sources = document.querySelectorAll("turbo-cable-stream-source[connected]")
        if (sources.length > 0) {
          // Stream sources still think they're connected but WS is dead
          this.setDisconnected()
          this.scheduleReconnect()
        }
      }
    }, 3000)
  }

  stopWebSocketMonitoring() {
    if (this.wsMonitorInterval) {
      clearInterval(this.wsMonitorInterval)
      this.wsMonitorInterval = null
    }
  }
}
