import { Controller } from "@hotwired/stimulus"
import { isMobileDevice } from "controllers/utils/device_utils"
import { attachAppletResultChannel } from "applet_result_channel"
import {
  appletFrameBackgroundColor,
  attachAppletThemeRequestResponder,
  syncAppletIframeTheme,
  themedAppletUrl
} from "applet_theme"

export default class extends Controller {
  static targets = [
    "chalkboard",
    "container",
    "host",
    "mobileOverlay",
    "screenshotModal",
    "screenshotDesktopCopy",
    "screenshotMobileCopy",
    "screenSizeWarning",
    "fixedTabs",
    "dynamicTabList",
    "appletContext",
    "appletSelect",
    "shareButton",
    "tabPanels",
    "appletsPanel",
    "whiteboardPanel",
    "dynamicPanels",
    "appletViewport",
    "appletEmptyState",
    "tabInbox",
    "inboxEvent",
    "seededApplets"
  ]

  connect() {
    // Placeholders for moving the chalkboard DOM between desktop sidebar and mobile overlay
    this._originalParent = null
    this._originalClasses = null
    this.activeTabId = null
    this.selectedAppletKey = null
    this.whiteboardInitialized = false
    this.tabRegistry = new Map()
    this.appletRegistry = new Map()

    // If we found the container, cache original parent and classes immediately
    if (this.containerTarget) {
      this._originalParent = this.containerTarget.parentNode
      this._originalClasses = this.containerTarget.className
    } else {
      console.warn("Chalkboard container (#chalkboard_container) not found on connect.")
    }

    this.registerCoreTabs()
    this.hydrateSeededApplets()
    this.sizeAppletSelectToOptions()
    this.updateScreenshotInstructionCopy()
    this.updateTabUi()

    this._registerAppletHandler = (event) => this.registerApplet(event.detail || {})
    this._openPushTabHandler = (event) => this.openPushTab(event.detail || {})
    this._boundThemeChangeHandler = () => this.syncAppletFrameThemes()
    this._boundEscapeHandler = (event) => {
      if (event.key === "Escape" && this.isMobileOpen()) this.closeMobile()
    }
    this._boundResizeHandler = () => {
      if (window.innerWidth >= 1280 && this.isMobileOpen()) {
        this.closeMobile()
      } else {
        this.sizeAppletSelectToOptions()
      }
    }
    this._boundScreenshotModalClose = (event) => this.handleScreenshotModalClose(event)
    window.addEventListener("chalkboard:register-applet", this._registerAppletHandler)
    window.addEventListener("chalkboard:open-push-tab", this._openPushTabHandler)
    window.addEventListener("goa:theme-change", this._boundThemeChangeHandler)
    window.addEventListener("resize", this._boundResizeHandler)
    this._detachThemeRequestResponder = attachAppletThemeRequestResponder(() => this.appletIframes())
    if (this.hasScreenshotModalTarget) {
      this.screenshotModalTarget.addEventListener("modal:close", this._boundScreenshotModalClose)
    }
  }

  disconnect() {
    // clean up listeners
    window.removeEventListener("chalkboard:register-applet", this._registerAppletHandler)
    window.removeEventListener("chalkboard:open-push-tab", this._openPushTabHandler)
    window.removeEventListener("goa:theme-change", this._boundThemeChangeHandler)
    window.removeEventListener("resize", this._boundResizeHandler)
    window.removeEventListener("keydown", this._boundEscapeHandler)
    this._detachThemeRequestResponder?.()
    if (this.hasScreenshotModalTarget) {
      this.screenshotModalTarget.removeEventListener("modal:close", this._boundScreenshotModalClose)
    }
    if (this.isMobileOpen()) {
      this.closeMobile()
    }
    this.appletRegistry.forEach((entry) => entry.detachResultChannel?.())
  }

  inboxEventTargetConnected(element) {
    this.consumeInboxEvent(element)
    element.remove()
  }

  consumeInboxEvent(element) {
    let payload = {}
    try {
      payload = JSON.parse(element.dataset.payload || "{}")
    } catch (_err) {
      return
    }

    if (payload.event_type === "register_applet") {
      this.registerApplet(payload)
      return
    }

    if (payload.event_type === "open_push_tab") {
      this.openPushTab(payload)
    }
  }

  registerCoreTabs() {
    this.tabRegistry.set("applets", {
      id: "applets",
      type: "core",
      panel: this.appletsPanelTarget,
      button: this.findTabButton("applets"),
      closable: false
    })

    this.tabRegistry.set("whiteboard", {
      id: "whiteboard",
      type: "core",
      panel: this.whiteboardPanelTarget,
      button: this.findTabButton("whiteboard"),
      closable: false
    })
  }

  findTabButton(tabId) {
    return this.containerTarget.querySelector(`[data-tab-id="${tabId}"]`)
  }

  activateTab(event) {
    const tabId = event.currentTarget.dataset.tabId
    this.activateTabById(tabId, { ensureContent: true })
  }

  activateTabById(tabId, { ensureContent = false } = {}) {
    const tab = this.tabRegistry.get(tabId)
    if (!tab) return

    this.activeTabId = tabId

    if (ensureContent && tabId === "whiteboard") {
      this.ensureWhiteboardPanel()
    }
    if (ensureContent && tabId === "applets") {
      this.ensureDefaultAppletSelection()
    }

    this.tabRegistry.forEach((entry) => {
      if (!entry.panel) return
      entry.panel.classList.toggle("hidden", entry.id !== tabId)
      this.setTabButtonActive(entry.button, entry.id === tabId)
    })

    this.appletContextTarget.classList.toggle("hidden", tabId !== "applets")
    this.appletContextTarget.classList.toggle("flex", tabId === "applets")

    this.updateAppletContext()
  }

  setTabButtonActive(button, active) {
    if (!button) return
    button.classList.toggle("bg-stone-200", active)
    button.classList.toggle("dark:bg-stone-700", active)
    button.classList.toggle("font-semibold", active)
  }

  updateTabUi() {
    this.tabRegistry.forEach((entry) => {
      this.setTabButtonActive(entry.button, entry.id === this.activeTabId)
      if (entry.panel) {
        entry.panel.classList.toggle("hidden", entry.id !== this.activeTabId)
      }
    })
    const appletsActive = this.activeTabId === "applets"
    this.appletContextTarget.classList.toggle("hidden", !appletsActive)
    this.appletContextTarget.classList.toggle("flex", appletsActive)
    this.updateAppletContext()
  }

  ensureWhiteboardPanel() {
    if (this.whiteboardInitialized) return

    const iframe = document.createElement("iframe")
    iframe.src = "https://excalidraw.com/"
    iframe.className = "h-full w-full"
    iframe.allow = "clipboard-read; clipboard-write;"
    iframe.dataset.chalkboardCacheKey = "whiteboard"
    this.whiteboardPanelTarget.appendChild(iframe)
    this.whiteboardInitialized = true
  }

  ensureDefaultAppletSelection() {
    if (!this.selectedAppletKey && this.appletRegistry.size > 0) {
      this.selectedAppletKey = Array.from(this.appletRegistry.keys())[0]
    }

    if (!this.selectedAppletKey) {
      this.appletEmptyStateTarget.classList.remove("hidden")
      this.appletViewportTarget.classList.add("hidden")
      this.updateAppletContext()
      return
    }

    this.appletSelectTarget.value = this.selectedAppletKey
    this.ensureAppletPanel(this.selectedAppletKey)
  }

  selectApplet(event) {
    const key = event.currentTarget.value
    if (!key) {
      this.selectedAppletKey = null
      Array.from(this.appletViewportTarget.children).forEach((child) => {
        child.classList.add("hidden")
      })
      this.appletViewportTarget.classList.add("hidden")
      this.appletEmptyStateTarget.classList.remove("hidden")
      this.updateAppletContext()
      if (window.innerWidth < 768) {
        window.requestAnimationFrame(() => event.currentTarget.blur())
      }
      return
    }
    this.selectedAppletKey = key
    this.ensureAppletPanel(key)
    this.updateAppletContext()
    if (window.innerWidth < 768) {
      window.requestAnimationFrame(() => event.currentTarget.blur())
    }
  }

  openAppletPicker(event) {
    if (event?.preventDefault) event.preventDefault()
    if (!this.hasAppletSelectTarget) return

    const select = this.appletSelectTarget
    try {
      if (typeof select.showPicker === "function") {
        select.showPicker()
      } else {
        select.focus()
        select.click()
      }
    } catch (_err) {
      select.focus()
      select.click()
    }
  }

  ensureAppletPanel(appletKey) {
    const entry = this.appletRegistry.get(appletKey)
    if (!entry) return

    if (!entry.panelElement) {
      const panel = document.createElement("div")
      panel.className = "h-full hidden"
      panel.dataset.appletKey = appletKey

      const iframe = document.createElement("iframe")
      iframe.title = entry.title || "Chalkboard Applet"
      iframe.sandbox = "allow-scripts allow-modals allow-pointer-lock allow-popups allow-presentation allow-forms allow-downloads"
      iframe.allow = "fullscreen; accelerometer *; encrypted-media *; gyroscope *; magnetometer *; gamepad *; midi *; clipboard-write *; local-fonts *; xr-spatial-tracking *"
      iframe.style.width = "100%"
      iframe.style.height = "100%"
      iframe.style.border = "0"
      iframe.style.backgroundColor = appletFrameBackgroundColor()
      iframe.dataset.chalkboardCacheKey = `applet:${appletKey}`
      if (entry.embed_srcdoc) {
        iframe.srcdoc = entry.embed_srcdoc
      } else if (entry.embed_src) {
        iframe.src = themedAppletUrl(entry.embed_src)
      } else if (entry.launch_url) {
        iframe.src = themedAppletUrl(entry.launch_url)
      }

      panel.appendChild(iframe)
      this.appletViewportTarget.appendChild(panel)
      entry.panelElement = panel
      if (entry.embed_srcdoc) {
        entry.detachResultChannel = attachAppletResultChannel(iframe, {
          conversationId: entry.conversationId,
          messageId: entry.messageId,
          title: entry.title,
          appletKey: entry.key
        })
      }
      this.appletRegistry.set(appletKey, entry)
    }

    Array.from(this.appletViewportTarget.children).forEach((child) => {
      child.classList.add("hidden")
    })
    entry.panelElement.classList.remove("hidden")
    this.appletViewportTarget.classList.remove("hidden")
    this.appletEmptyStateTarget.classList.add("hidden")
  }

  hydrateSeededApplets() {
    if (!this.hasSeededAppletsTarget) return

    let payload = []
    try {
      payload = JSON.parse(this.seededAppletsTarget.dataset.appletsJson || "[]")
    } catch (_err) {
      payload = []
    }

    payload.forEach((entry) => this.registerApplet(entry, { focus: false }))
  }

  registerApplet(payload, { focus = false } = {}) {
    const key = payload.key || (payload.applet_id ? `linked_${payload.applet_id}` : `jit_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`)
    const entry = {
      key: key,
      source: payload.source || "jit",
      applet_id: payload.applet_id || null,
      title: payload.title || "Generated Applet",
      launch_url: payload.launch_url || null,
      embed_src: payload.embed_src || null,
      embed_srcdoc: payload.embed_srcdoc || null,
      shareable: payload.shareable === true,
      share_url: this.absoluteUrl(payload.share_url),
      conversationId: payload.conversation_id || this.appletRegistry.get(key)?.conversationId || null,
      messageId: payload.message_id || this.appletRegistry.get(key)?.messageId || null,
      panelElement: this.appletRegistry.get(key)?.panelElement || null,
      detachResultChannel: this.appletRegistry.get(key)?.detachResultChannel || null
    }

    this.appletRegistry.set(key, entry)
    this.rebuildAppletSelect()

    if (!this.selectedAppletKey) {
      this.selectedAppletKey = key
    }

    if (payload.auto_open_in_board === true) {
      focus = true
    }

    if (focus) {
      this.selectedAppletKey = key
      this.activateTabById("applets", { ensureContent: true })
    } else if (this.activeTabId === "applets" && this.selectedAppletKey === key) {
      this.ensureAppletPanel(key)
      this.updateAppletContext()
    }
  }

  rebuildAppletSelect() {
    const previousValue = this.selectedAppletKey
    this.appletSelectTarget.innerHTML = ""

    const placeholder = document.createElement("option")
    placeholder.value = ""
    placeholder.textContent = "Select applet..."
    this.appletSelectTarget.appendChild(placeholder)

    this.appletRegistry.forEach((entry, key) => {
      const option = document.createElement("option")
      option.value = key
      option.textContent = entry.title
      this.appletSelectTarget.appendChild(option)
    })

    if (previousValue && this.appletRegistry.has(previousValue)) {
      this.appletSelectTarget.value = previousValue
    } else if (this.appletRegistry.size > 0) {
      this.selectedAppletKey = Array.from(this.appletRegistry.keys())[0]
      this.appletSelectTarget.value = this.selectedAppletKey
    } else {
      this.selectedAppletKey = null
      this.appletSelectTarget.value = ""
    }
    this.sizeAppletSelectToOptions()
    this.updateAppletContext()
  }

  currentAppletEntry() {
    return this.selectedAppletKey ? this.appletRegistry.get(this.selectedAppletKey) : null
  }

  updateAppletContext() {
    const current = this.currentAppletEntry()
    const canShare = this.activeTabId === "applets" && !!(current?.shareable && current?.share_url)

    if (!current) {
      this.shareButtonTarget.classList.add("hidden")
      this.shareButtonTarget.classList.remove("inline-flex")
      return
    }

    this.shareButtonTarget.classList.toggle("hidden", !canShare)
    this.shareButtonTarget.classList.toggle("inline-flex", canShare)
    this.shareButtonTarget.title = "Copy private applet link"
  }

  sizeAppletSelectToOptions() {
    if (!this.hasAppletSelectTarget) return

    const select = this.appletSelectTarget
    if (window.innerWidth < 768) {
      select.style.width = ""
      return
    }
    const options = Array.from(select.options)
    if (options.length === 0) return

    const textToMeasure = options.map((option) => option.text || "")
    const canvas = this._textMeasureCanvas || document.createElement("canvas")
    this._textMeasureCanvas = canvas
    const ctx = canvas.getContext("2d")
    if (!ctx) return

    const computed = window.getComputedStyle(select)
    ctx.font = `${computed.fontStyle} ${computed.fontVariant} ${computed.fontWeight} ${computed.fontSize} ${computed.fontFamily}`

    const widestText = textToMeasure.reduce((max, text) => Math.max(max, ctx.measureText(text).width), 0)
    const minWidthPx = 160
    const maxWidthPx = 448
    const chromePaddingPx = 56 // left/right padding plus caret room
    const desired = Math.ceil(widestText + chromePaddingPx)
    const clamped = Math.max(minWidthPx, Math.min(maxWidthPx, desired))
    select.style.width = `${clamped}px`
  }

  absoluteUrl(url) {
    if (!url) return null
    try {
      return new URL(url, window.location.origin).toString()
    } catch (_err) {
      return url
    }
  }

  syncAppletFrameThemes() {
    this.appletIframes().forEach((iframe) => syncAppletIframeTheme(iframe))
  }

  appletIframes() {
    if (!this.hasAppletViewportTarget) return []
    return Array.from(this.appletViewportTarget.querySelectorAll("iframe"))
  }

  async shareCurrentApplet() {
    const current = this.currentAppletEntry()
    if (!current || !current.shareable || !current.share_url) return

    const shareUrl = this.absoluteUrl(current.share_url)
    if (!shareUrl) return

    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(shareUrl)
      } else {
        window.prompt("Copy applet link:", shareUrl)
      }
      this.showShareCopiedState()
    } catch (_err) {
      window.prompt("Copy applet link:", shareUrl)
    }
  }

  showShareCopiedState() {
    const icon = this.shareButtonTarget.querySelector("sl-icon")
    const originalName = icon?.name || "share"
    if (icon) icon.name = "check2"
    window.setTimeout(() => {
      if (icon) icon.name = originalName
      this.updateAppletContext()
    }, 1200)
  }

  openPushTab(payload) {
    const tabId = payload.tab_id || `push_${Date.now()}`
    const existing = this.tabRegistry.get(tabId)
    if (existing) {
      this.activateTabById(tabId, { ensureContent: false })
      return
    }

    const panel = document.createElement("div")
    panel.className = "hidden h-full overflow-auto rounded border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-950 p-4 prose dark:prose-invert max-w-none"
    panel.dataset.tabPanelId = tabId
    panel.innerHTML = payload.content_html || ""
    this.dynamicPanelsTarget.appendChild(panel)

    const tabWrapper = document.createElement("div")
    tabWrapper.className = "flex items-center rounded border border-stone-400 dark:border-stone-600 overflow-hidden"

    const tabButton = document.createElement("button")
    tabButton.type = "button"
    tabButton.className = "text-xs px-2 py-1 max-w-40 truncate hover:bg-stone-200 dark:hover:bg-stone-800"
    tabButton.dataset.tabId = tabId
    tabButton.textContent = payload.tab_title || "Board"
    tabButton.addEventListener("click", () => this.activateTabById(tabId, { ensureContent: false }))
    tabWrapper.appendChild(tabButton)

    const closeButton = document.createElement("button")
    closeButton.type = "button"
    closeButton.className = "px-1 py-1 text-xs border-l border-stone-400 dark:border-stone-600 hover:bg-stone-200 dark:hover:bg-stone-800"
    closeButton.textContent = "x"
    closeButton.title = "Close tab"
    closeButton.addEventListener("click", () => this.closeDynamicTab(tabId))
    tabWrapper.appendChild(closeButton)

    this.dynamicTabListTarget.appendChild(tabWrapper)

    this.tabRegistry.set(tabId, {
      id: tabId,
      type: "dynamic",
      kind: payload.kind || "push",
      panel: panel,
      button: tabButton,
      wrapper: tabWrapper,
      closable: true
    })

    this.activateTabById(tabId, { ensureContent: false })
  }

  closeDynamicTab(tabId) {
    const tab = this.tabRegistry.get(tabId)
    if (!tab || tab.type !== "dynamic") return

    tab.panel?.remove()
    tab.wrapper?.remove()
    this.tabRegistry.delete(tabId)

    if (this.activeTabId === tabId) {
      this.activeTabId = null
      this.updateTabUi()
    }
  }

  isMobileOpen() {
    return this.hasMobileOverlayTarget && !this.mobileOverlayTarget.classList.contains("hidden")
  }

  openMobile(event) {
    if (event?.preventDefault) event.preventDefault()
    if (!this.hasMobileOverlayTarget || !this.hasHostTarget) return
    if (window.innerWidth >= 1280) return

    if (!this._originalParent) {
      this._originalParent = this.containerTarget.parentNode
      this._originalClasses = this.containerTarget.className
    }

    // Move the entire chalkboard container into the mobile overlay host
    if (!this.hostTarget.contains(this.containerTarget)) {
      this.hostTarget.appendChild(this.containerTarget)
      // Make sure it's visible and fills the overlay
      this.containerTarget.classList.remove("hidden", "xl:flex", "xl:flex-col", "xl:grow")
      this.containerTarget.classList.add("flex", "flex-col", "h-full", "w-full")
    }

    this.mobileOverlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    window.addEventListener("keydown", this._boundEscapeHandler)
  }

  closeMobile(event) {
    if (event?.preventDefault) event.preventDefault()

    if (this.hasMobileOverlayTarget) {
      this.mobileOverlayTarget.classList.add("hidden")
    }
    document.body.classList.remove("overflow-hidden")
    window.removeEventListener("keydown", this._boundEscapeHandler)

    // Move the chalkboard back to its original parent and restore classes
    if (this._originalParent) {
      this._originalParent.appendChild(this.containerTarget)
      if (typeof this._originalClasses === "string") {
        this.containerTarget.className = this._originalClasses
      }
    } else if (this.hasContainerTarget) {
      console.warn("Original parent not cached; nothing to restore.")
    }
  }

  printChalkboard() {
    document.body.classList.add("invisible")
    if (this.hasChalkboardTarget) {
      this.chalkboardTarget.classList.add("visible", "absolute", "top-0", "left-0", "h-full", "w-full")
      window.print()
      this.chalkboardTarget.classList.remove("visible", "absolute", "top-0", "left-0", "h-full", "w-full")
    } else {
      console.warn("No chalkboard target available for printing.");
    }
    document.body.classList.remove("invisible")
  }

  screenshotInstructions() {
    if (this.hasScreenshotModalTarget) {
      this.screenshotModalTarget.dispatchEvent(new CustomEvent("chalkboard:screenshot-modal-open", { bubbles: true }))
    } else {
      console.warn("No screenshot modal target found.")
    }
  }

  handleScreenshotModalClose(event) {
    if (event?.detail?.reason !== "browser-screenshot") return

    this.dispatch("browser-screenshot-request", { bubbles: true })
  }

  updateScreenshotInstructionCopy() {
    if (!this.hasScreenshotDesktopCopyTarget || !this.hasScreenshotMobileCopyTarget) return
    const mobile = isMobileDevice()
    this.screenshotDesktopCopyTarget.classList.toggle("hidden", mobile)
    this.screenshotMobileCopyTarget.classList.toggle("hidden", !mobile)
  }

  openWhiteboard() {
    this.activateTabById("whiteboard", { ensureContent: true })
  }
}
