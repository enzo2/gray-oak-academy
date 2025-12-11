import { Controller } from "@hotwired/stimulus"

/**
 * Connection Debug Controller
 *
 * A developer tool for testing WebSocket connection dropout scenarios.
 * Use in browser console: window.ConnectionDebug
 *
 * Methods:
 * - disconnect() - Close the WebSocket connection
 * - removeConnectedAttr() - Remove connected attribute from stream sources
 * - goOffline() / goOnline() - Simulate network state changes
 * - status() - Show current connection status
 * - monitor() - Start logging all connection events
 */
export default class extends Controller {
  connect() {
    // Expose debug methods globally for console access
    window.ConnectionDebug = {
      disconnect: this.forceDisconnect.bind(this),
      removeConnectedAttr: this.removeConnectedAttribute.bind(this),
      goOffline: this.simulateOffline.bind(this),
      goOnline: this.simulateOnline.bind(this),
      status: this.showStatus.bind(this),
      monitor: this.startMonitoring.bind(this),
      help: this.showHelp.bind(this)
    }

    console.log("%c🔌 ConnectionDebug loaded. Type ConnectionDebug.help() for commands.", "color: #22c55e; font-weight: bold;")
  }

  disconnect() {
    delete window.ConnectionDebug
  }

  showHelp() {
    console.log(`
%c🔌 Connection Debug Commands:

%cConnectionDebug.status()%c
  Show current WebSocket and stream source status

%cConnectionDebug.disconnect()%c
  Close the WebSocket connection (simulates network dropout)
  This is the most realistic dropout simulation.

%cConnectionDebug.removeConnectedAttr()%c
  Remove the 'connected' attribute from stream sources
  Triggers the MutationObserver in connection_status_controller

%cConnectionDebug.goOffline()%c
  Dispatch 'offline' event (simulates browser going offline)

%cConnectionDebug.goOnline()%c
  Dispatch 'online' event (simulates browser coming back online)

%cConnectionDebug.monitor()%c
  Start logging all connection-related events to console
`,
      "color: #22c55e; font-weight: bold; font-size: 14px;",
      "color: #3b82f6; font-weight: bold;", "color: inherit;",
      "color: #3b82f6; font-weight: bold;", "color: inherit;",
      "color: #3b82f6; font-weight: bold;", "color: inherit;",
      "color: #3b82f6; font-weight: bold;", "color: inherit;",
      "color: #3b82f6; font-weight: bold;", "color: inherit;",
      "color: #3b82f6; font-weight: bold;", "color: inherit;"
    )
  }

  showStatus() {
    const cable = this.getCable()
    const ws = cable?.connection?.webSocket
    const wsStates = ["CONNECTING", "OPEN", "CLOSING", "CLOSED"]

    const sources = document.querySelectorAll("turbo-cable-stream-source")
    const connectedSources = document.querySelectorAll("turbo-cable-stream-source[connected]")

    const indicator = document.querySelector("[data-connection-status-target='indicator']")
    const indicatorConnected = indicator?.classList.contains("text-success-600") ||
                               indicator?.classList.contains("dark:text-success-500")

    console.log(`
%c🔌 Connection Status:

%cWebSocket:%c ${ws ? wsStates[ws.readyState] : "Not found"} ${ws ? `(readyState: ${ws.readyState})` : ""}
%cActionCable:%c ${cable?.connection?.disconnected ? "Disconnected" : "Connected"}
%cStream Sources:%c ${connectedSources.length}/${sources.length} connected
%cUI Indicator:%c ${indicatorConnected ? "✅ Connected (green)" : "❌ Disconnected (red)"}
%cOnline Status:%c ${navigator.onLine ? "Online" : "Offline"}
`,
      "color: #22c55e; font-weight: bold; font-size: 14px;",
      "color: #94a3b8; font-weight: bold;", "color: inherit;",
      "color: #94a3b8; font-weight: bold;", "color: inherit;",
      "color: #94a3b8; font-weight: bold;", "color: inherit;",
      "color: #94a3b8; font-weight: bold;", "color: inherit;",
      "color: #94a3b8; font-weight: bold;", "color: inherit;"
    )

    return {
      webSocket: ws ? wsStates[ws.readyState] : null,
      actionCableConnected: cable?.connection?.disconnected === false,
      streamSourcesConnected: connectedSources.length,
      streamSourcesTotal: sources.length,
      indicatorShowsConnected: indicatorConnected,
      browserOnline: navigator.onLine
    }
  }

  forceDisconnect() {
    const cable = this.getCable()
    const ws = cable?.connection?.webSocket

    if (ws && ws.readyState === WebSocket.OPEN) {
      console.log("%c🔌 Closing WebSocket connection...", "color: #ef4444; font-weight: bold;")
      ws.close()
      return true
    } else if (ws) {
      console.log(`%c🔌 WebSocket not open (state: ${ws.readyState})`, "color: #f59e0b;")
      return false
    } else {
      console.log("%c🔌 No WebSocket found", "color: #ef4444;")
      return false
    }
  }

  removeConnectedAttribute() {
    const sources = document.querySelectorAll("turbo-cable-stream-source[connected]")

    if (sources.length === 0) {
      console.log("%c🔌 No connected stream sources found", "color: #f59e0b;")
      return false
    }

    console.log(`%c🔌 Removing 'connected' attribute from ${sources.length} source(s)...`, "color: #ef4444; font-weight: bold;")
    sources.forEach(source => source.removeAttribute("connected"))
    return true
  }

  simulateOffline() {
    console.log("%c🔌 Simulating offline event...", "color: #ef4444; font-weight: bold;")
    window.dispatchEvent(new Event("offline"))
  }

  simulateOnline() {
    console.log("%c🔌 Simulating online event...", "color: #22c55e; font-weight: bold;")
    window.dispatchEvent(new Event("online"))
  }

  startMonitoring() {
    if (this.monitoring) {
      console.log("%c🔌 Already monitoring", "color: #f59e0b;")
      return
    }

    this.monitoring = true
    console.log("%c🔌 Monitoring connection events... (refresh page to stop)", "color: #22c55e; font-weight: bold;")

    document.addEventListener("turbo:stream-connected", (e) => {
      console.log("%c🔌 turbo:stream-connected", "color: #22c55e; font-weight: bold;", e.detail)
    })

    document.addEventListener("turbo:stream-disconnected", (e) => {
      console.log("%c🔌 turbo:stream-disconnected", "color: #ef4444; font-weight: bold;", e.detail)
    })

    window.addEventListener("online", () => {
      console.log("%c🔌 Browser online", "color: #22c55e; font-weight: bold;")
    })

    window.addEventListener("offline", () => {
      console.log("%c🔌 Browser offline", "color: #ef4444; font-weight: bold;")
    })

    // Monitor WebSocket state changes
    const cable = this.getCable()
    if (cable?.connection?.webSocket) {
      const ws = cable.connection.webSocket
      const originalOnClose = ws.onclose
      ws.onclose = (event) => {
        console.log("%c🔌 WebSocket closed", "color: #ef4444; font-weight: bold;", event)
        if (originalOnClose) originalOnClose.call(ws, event)
      }
      const originalOnOpen = ws.onopen
      ws.onopen = (event) => {
        console.log("%c🔌 WebSocket opened", "color: #22c55e; font-weight: bold;", event)
        if (originalOnOpen) originalOnOpen.call(ws, event)
      }
      const originalOnError = ws.onerror
      ws.onerror = (event) => {
        console.log("%c🔌 WebSocket error", "color: #ef4444; font-weight: bold;", event)
        if (originalOnError) originalOnError.call(ws, event)
      }
    }
  }

  getCable() {
    // First check turbo-cable-stream-source elements for their subscription's consumer
    const source = document.querySelector("turbo-cable-stream-source")
    if (source?.subscription?.consumer) {
      return source.subscription.consumer
    }
    // Fallback to global locations
    return window.Turbo?.cable ||
           window.ActionCable?.consumer ||
           window.App?.cable ||
           window.consumer
  }
}
