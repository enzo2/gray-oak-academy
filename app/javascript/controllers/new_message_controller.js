import { Controller } from "@hotwired/stimulus"
import { isMobileDevice } from "controllers/utils/device_utils"

// Handles the message form in LLM conversations
// Enables image uploads, URL image previews, pasting images, shift+enter for new lines, and form submission
export default class extends Controller {
  static targets = [
    "fileInput",
    "urlInput",
    "previewArea",
    "contentField",
    "imagesData",
    "appletResultsData",
    "imagesMenuButton",
    "imagesMenu",
    "urlDialog",
    "submitButton",
    "submitSpinner",
    "submitIcon",
    "helpText",
    "cameraMenuItem",
    "screenshotMenuItem"
  ];
  static values = { audioSetting: String, conversationId: String };
  static MAX_IMAGES = 4;
  static CAPTURE_START_DELAY_MS = 150;

  connect() {
    //console.log("New message controller connected")
    this.images = []
    this.appletResults = new Map() // keyed by applet; buffered until the student sends
    this.busy = false
    this.boundHandleMenuSelect = this.handleMenuSelect.bind(this)
    this.boundReceiveAppletResult = this.receiveAppletResult.bind(this)
    window.addEventListener("applet:result", this.boundReceiveAppletResult)
    this.boundHandleCompletionFinished = this.handleCompletionFinished.bind(this)
    this.boundHandleCompletionError = this.handleCompletionError.bind(this)
    this.boundHandleSubmitEnd = this.handleSubmitEnd.bind(this)
    this.imagesMenuTarget.addEventListener('sl-select', this.boundHandleMenuSelect)
    document.addEventListener("llm-completion-finished", this.boundHandleCompletionFinished)
    document.addEventListener("llm-completion-error", this.boundHandleCompletionError)
    this.element.addEventListener("turbo:submit-end", this.boundHandleSubmitEnd)
    this.browserScreenshotSupported = Boolean(navigator.mediaDevices?.getDisplayMedia)
    this.offerBrowserScreenshot = this.browserScreenshotSupported && !isMobileDevice()
    if (this.hasCameraMenuItemTarget) {
      this.cameraMenuItemTarget.classList.add("hidden")
    }
    if (this.hasScreenshotMenuItemTarget) {
      this.screenshotMenuItemTarget.classList.toggle("hidden", !this.offerBrowserScreenshot)
    }

    const initialBusy = this.currentBusyState() || this.detectBusyFromDom()
    if (this.hasConversationIdValue) {
      this.setBusyState(initialBusy)
    } else {
      this.applyBusyState(initialBusy)
    }

    this.dispatch("camera-check", { bubbles: true })
  }

  /* It's annoying to autofocus on mobile since the keyboard pops up 
  async contentFieldTargetConnected() {
    await Promise.allSettled([
      customElements.whenDefined('sl-textarea')
    ]);
    //this.contentFieldTarget.focus()
  } */
    

  toggleSubmitButton() {
    if (this.busy) return

    const hasContent = this.contentFieldTarget.value.trim() !== '' || this.images.length > 0 || this.appletResults.size > 0;
    if (this.audioSettingValue === "only" && !hasContent) {
      this.helpTextTarget.classList.remove("hidden");
      return;
    }

    //console.log("toggleSubmitButton")
    if (hasContent) {
      this.submitIconTarget.classList.remove("hidden");
    } else {
      this.submitIconTarget.classList.add("hidden");
    }
  }

  handleMenuSelect(event) {
    //console.log("Handling menu select", event.detail.item.value)
    if (event.detail.item.value === 'file') {
      this.fileInputTarget.click()
    } else if (event.detail.item.value === 'url') {
      this.urlDialogTarget.show()
    } else if (event.detail.item.value === 'camera') {
      this.openCamera()
    } else if (event.detail.item.value === 'screenshot') {
      if (!this.offerBrowserScreenshot) return
      this.captureBrowserScreenshotUncropped()
    }
  }

  openCamera() {
    if (this.busy) return
    this.dispatch("camera-open", { bubbles: true })
  }

  async captureBrowserScreenshot() {
    if (this.busy) return
    if (!this.canAddMoreImages()) return

    if (!navigator.mediaDevices?.getDisplayMedia) {
      alert("Browser screenshot capture is not supported here. Use your system screenshot tool and paste into chat.")
      return
    }

    let stream = null
    try {
      const cropHint = this.chalkboardCropHint()
      stream = await this.openDisplayMediaStream({ preferCurrentTab: true })
      await this.waitBeforeFrameCapture()
      if (this.busy) return

      const blob = await this.captureScreenshotBlob(stream, cropHint)
      if (!blob) {
        alert("Could not capture screenshot. Please try again.")
        return
      }

      const file = new File([blob], "browser-screenshot.png", { type: blob.type || "image/png" })
      this.addImage(file)
    } catch (error) {
      if (error?.name === "NotAllowedError" || error?.name === "AbortError") return
      alert("Failed to capture screenshot. Try your system screenshot tool and paste into chat.")
      console.error("Screen Capture API failed:", error)
    } finally {
      stream?.getTracks().forEach((track) => track.stop())
    }
  }

  async captureBrowserScreenshotUncropped() {
    if (this.busy) return
    if (!this.canAddMoreImages()) return

    if (!navigator.mediaDevices?.getDisplayMedia) {
      alert("Browser screenshot capture is not supported here. Use your system screenshot tool and paste into chat.")
      return
    }

    let stream = null
    try {
      stream = await this.openDisplayMediaStream()
      await this.waitBeforeFrameCapture()
      if (this.busy) return

      const blob = await this.captureScreenshotBlob(stream)
      if (!blob) {
        alert("Could not capture screenshot. Please try again.")
        return
      }

      const file = new File([blob], "browser-screenshot.png", { type: blob.type || "image/png" })
      this.addImage(file)
    } catch (error) {
      if (error?.name === "NotAllowedError" || error?.name === "AbortError") return
      alert("Failed to capture screenshot. Try your system screenshot tool and paste into chat.")
      console.error("Screen Capture API failed:", error)
    } finally {
      stream?.getTracks().forEach((track) => track.stop())
    }
  }

  async openDisplayMediaStream({ preferCurrentTab = false } = {}) {
    const attempts = []
    if (preferCurrentTab) {
      attempts.push({
        video: { cursor: "never" },
        audio: false,
        preferCurrentTab: true
      })
    }
    attempts.push({
      video: { cursor: "never" },
      audio: false
    })
    attempts.push({
      video: true,
      audio: false
    })

    let lastError = null
    for (const constraints of attempts) {
      try {
        return await navigator.mediaDevices.getDisplayMedia(constraints)
      } catch (error) {
        if (error?.name === "NotAllowedError" || error?.name === "AbortError") throw error
        lastError = error
      }
    }

    throw lastError || new Error("Failed to start display capture")
  }

  waitBeforeFrameCapture() {
    return new Promise((resolve) => {
      window.setTimeout(resolve, this.constructor.CAPTURE_START_DELAY_MS)
    })
  }

  captureScreenshotBlob(stream, cropHint = null) {
    return new Promise((resolve, reject) => {
      const video = document.createElement("video")
      video.srcObject = stream
      video.muted = true
      video.playsInline = true

      const cleanup = () => {
        video.pause()
        video.srcObject = null
      }

      video.onloadedmetadata = async () => {
        try {
          await video.play()
          const frameWidth = video.videoWidth
          const frameHeight = video.videoHeight
          if (!frameWidth || !frameHeight) {
            cleanup()
            resolve(null)
            return
          }

          const crop = this.cropRectFromHint(cropHint, frameWidth, frameHeight)
          const canvas = document.createElement("canvas")
          canvas.width = crop.width
          canvas.height = crop.height
          const context = canvas.getContext("2d")
          if (!context) {
            cleanup()
            resolve(null)
            return
          }

          context.drawImage(
            video,
            crop.x,
            crop.y,
            crop.width,
            crop.height,
            0,
            0,
            crop.width,
            crop.height
          )
          canvas.toBlob((blob) => {
            cleanup()
            resolve(blob)
          }, "image/png")
        } catch (error) {
          cleanup()
          reject(error)
        }
      }

      video.onerror = () => {
        cleanup()
        reject(new Error("Failed to read captured stream"))
      }
    })
  }

  chalkboardCropHint() {
    const container = document.getElementById("chalkboard") || document.getElementById("chalkboard_container")
    if (!container) return null

    const rect = container.getBoundingClientRect()
    if (rect.width <= 1 || rect.height <= 1) return null

    const viewportWidth = window.innerWidth || document.documentElement.clientWidth
    const viewportHeight = window.innerHeight || document.documentElement.clientHeight
    if (!viewportWidth || !viewportHeight) return null

    return {
      xRatio: this.clamp01(rect.left / viewportWidth),
      yRatio: this.clamp01(rect.top / viewportHeight),
      widthRatio: this.clamp01(rect.width / viewportWidth),
      heightRatio: this.clamp01(rect.height / viewportHeight),
      viewportAspect: viewportWidth / viewportHeight
    }
  }

  cropRectFromHint(cropHint, frameWidth, frameHeight) {
    const fullFrame = { x: 0, y: 0, width: frameWidth, height: frameHeight }
    if (!cropHint) return fullFrame

    let contentX = 0
    let contentY = 0
    let contentWidth = frameWidth
    let contentHeight = frameHeight

    // Some browsers provide capture frames with letterboxing around the tab content.
    // Fit a viewport-aspect content box first, then map ratio-based crop coordinates inside it.
    const viewportAspect = cropHint.viewportAspect
    if (Number.isFinite(viewportAspect) && viewportAspect > 0) {
      const frameAspect = frameWidth / frameHeight
      if (Number.isFinite(frameAspect) && frameAspect > 0) {
        if (frameAspect > viewportAspect) {
          contentHeight = frameHeight
          contentWidth = Math.round(contentHeight * viewportAspect)
          contentX = Math.round((frameWidth - contentWidth) / 2)
        } else if (frameAspect < viewportAspect) {
          contentWidth = frameWidth
          contentHeight = Math.round(contentWidth / viewportAspect)
          contentY = Math.round((frameHeight - contentHeight) / 2)
        }
      }
    }

    const x = Math.round(contentX + (cropHint.xRatio * contentWidth))
    const y = Math.round(contentY + (cropHint.yRatio * contentHeight))
    const width = Math.round(cropHint.widthRatio * contentWidth)
    const height = Math.round(cropHint.heightRatio * contentHeight)

    const safeX = Math.max(0, Math.min(x, frameWidth - 1))
    const safeY = Math.max(0, Math.min(y, frameHeight - 1))
    const safeWidth = Math.max(1, Math.min(width, frameWidth - safeX))
    const safeHeight = Math.max(1, Math.min(height, frameHeight - safeY))

    return { x: safeX, y: safeY, width: safeWidth, height: safeHeight }
  }

  clamp01(value) {
    return Math.max(0, Math.min(1, value))
  }
  
  canAddMoreImages() {
    if (this.busy) return false

    if (this.images.length >= this.constructor.MAX_IMAGES) {
      alert(`You can only add up to ${this.constructor.MAX_IMAGES} images per message.`)
      return false
    }
    return true
  }

  handleFiles(event) {
    //console.log("Handling files")
    const files = Array.from(event.target.files)
    files.forEach(file => {
      if (!this.canAddMoreImages()) return
      if (!this.validateImage(file)) return
      this.addImage(file)
    })
    this.fileInputTarget.value = null
  }

  closeUrlDialog() {
    this.urlDialogTarget.hide();
  }

  async handleUrlInput() {
    if (this.busy) return

    const url = this.urlInputTarget.value
    if (!this.canAddMoreImages()) return
    
    if (!URL.canParse(url)) {
      alert("Invalid URL.")
      return
    }

    try {
      const proxyUrl = `/proxy/image?url=${encodeURIComponent(url)}`
      const response = await fetch(proxyUrl, { method: 'HEAD' })
      if (!response.ok) {
        alert("Failed to validate image URL. Please ensure the URL is accessible. Status: " + response.statusText + " (" + response.status + ")")
        return
      }
      const contentType = response.headers.get('Content-Type').split(';')[0]
      if (!["image/png", "image/jpeg", "image/webp"].includes(contentType)) {
        alert("Invalid image type. Only PNG, JPEG, and WebP are allowed.")
        return
      }
      this.addImage({ url: url, type: contentType })
    } catch (error) {
      alert("Failed to validate image URL. Please ensure the URL is correct. Error: " + error.message)
      return
    }

    this.urlInputTarget.value = ""
    this.urlDialogTarget.hide()
  }

  validateImage(file) {
    if (!["image/png", "image/jpeg", "image/webp"].includes(file.type)) {
      alert("Invalid image type. Only PNG, JPEG, and WebP are allowed.");
      return false
    }
    if (file.size > 5 * 1024 * 1024) { // 5MB limit
      alert("Image size must be less than 5MB.");
      return false
    }
    return true
  }

  // Adds an image to the images array and updates the preview
  // Supports both URL images and file uploads
  addImage(image) {
    //console.log("Adding image", image)
    if (image.url) {
      this.images.push(image)
      this.updateImagesData()
      this.updatePreview()
    } else {
      if (!this.validateImage(image)) return;
      const reader = new FileReader()
      reader.onload = (e) => {
        this.images.push({
          data: e.target.result,
          type: image.type,
          name: image.name
        })
        this.updateImagesData()
        this.updatePreview()
      }
      reader.readAsDataURL(image)
    }
  }

  // Handles screenshot event from chalkboard_controller
  addScreenshotFromEvent(event) {
    if (this.busy) return

    //console.log("Adding screenshot from event", event);
    if (event && event.detail && event.detail.blob) {
      if (!this.canAddMoreImages()) return;
      const blob = event.detail.blob;
      const file = new File([blob], 'chalkboard.png', { type: blob.type || 'image/png' });
      this.addImage(file);
    }
  }

  addCameraPhoto(event) {
    if (this.busy) return

    const file = event?.detail?.file
    if (!file) return
    if (!this.canAddMoreImages()) return
    this.addImage(file)
  }

  setCameraAvailability(event) {
    const available = Boolean(event?.detail?.available)
    if (this.hasCameraMenuItemTarget) {
      this.cameraMenuItemTarget.classList.toggle("hidden", !available)
    }
  }

  updatePreview() {
    //console.log("Updating preview")
    this.previewAreaTarget.innerHTML = ""
    if (this.images.length === 0 && this.appletResults.size === 0) {
      this.previewAreaTarget.classList.add("hidden")
    } else {
      this.previewAreaTarget.classList.remove("hidden")
    }
    this.appletResults.forEach((result, key) => {
      const chip = document.createElement('div')
      chip.className = "relative flex items-start gap-1.5 rounded-md border border-moss/40 bg-white/70 px-3 py-1.5 pr-7 text-sm text-stone-700 dark:bg-stone-800/70 dark:text-stone-200"
      const display = this.summarizeAppletData(result.data) || result.title || "Applet result"
      chip.innerHTML = `
        <sl-icon name="controller" class="mt-0.5 shrink-0"></sl-icon>
        <span>${this.escapeHtml(display)}</span>
        <sl-icon-button name="x"
          data-action="click->new-message#removeAppletResult"
          data-applet-key="${this.escapeHtml(key)}"
          class="absolute top-0 right-0 text-stone-500"></sl-icon-button>`
      this.previewAreaTarget.appendChild(chip)
    })
    this.images.forEach((image, index) => {
      // Create a div for each image preview and append it to the previewAreaTarget 
      const previewElement = document.createElement('div')
      previewElement.classList.add('relative')
      if (image.url) {
        previewElement.innerHTML = `
          <img src="${image.url}" class="h-16 w-16 sm:h-20 sm:w-20 object-cover rounded-sm" alt="Image ${index + 1}">
          <sl-icon-button name="x"
            data-action="click->new-message#removeImage" 
            data-index="${index}" 
            class="absolute top-0 right-0 bg-stone-500 rounded-md [&::part(base)]:p-[4px] text-white">
          </sl-icon-button>`
      } else {
        previewElement.innerHTML = `
          <img src="${image.data}" class="h-16 w-16 sm:h-20 sm:w-20 object-cover rounded-sm" alt="Image ${index + 1}">
          <span class="block text-xs mt-1 text-center max-w-[4.5rem]">${image.name.length > 15 ? `${image.name.slice(0, 10)}...${image.name.slice(-5)}` : image.name}</span>
          <sl-icon-button name="x"
            data-action="click->new-message#removeImage" 
            data-index="${index}" 
            class="absolute top-0 right-0 bg-stone-500 rounded-md [&::part(base)]:p-[4px] text-white">
          </sl-icon-button>`
      }
      this.previewAreaTarget.appendChild(previewElement)
    })
    this.toggleSubmitButton()
  }

  removeImage(event) {
    //console.log("Removing image")
    const button = event.target.closest('sl-icon-button')
    if (button) {
      const index = button.dataset.index
      this.images.splice(index, 1)
      this.updateImagesData()
      this.updatePreview()
    } else {
      console.error("Remove button not found")
    }
  }

  updateImagesData() {
    //console.log("Updating images data")
    const processedImages = this.images.map(image => {
      if (image.url) {
        return { 
          url: image.url,
          type: image.type
        }
      } else {
        return {
          data: image.data,
          type: image.type,
          name: image.name
        }
      }
    })
    this.imagesDataTarget.value = JSON.stringify(processedImages)
  }

  // An applet reported a result. Buffer it as a pending attachment (one entry
  // per applet, updated in place so repeated reports never stack or spam turns),
  // then either wait for the student to send, or auto-send if the applet asked.
  receiveAppletResult(event) {
    const detail = event.detail || {}
    if (detail.type !== "result") return // progress/event are not buffered
    if (detail.conversationId && this.hasConversationIdValue &&
        String(detail.conversationId) !== String(this.conversationIdValue)) return

    const key = detail.appletKey || "default"
    this.appletResults.set(key, { title: detail.title || "Applet", data: detail.data ?? null })
    this.updateAppletResultsData()
    this.updatePreview()

    if (detail.send === true) this.maybeSubmit()
  }

  removeAppletResult(event) {
    const button = event.target.closest('sl-icon-button')
    if (!button) return
    this.appletResults.delete(button.dataset.appletKey)
    this.updateAppletResultsData()
    this.updatePreview()
  }

  updateAppletResultsData() {
    if (!this.hasAppletResultsDataTarget) return
    const results = Array.from(this.appletResults.entries()).map(([key, value]) => ({
      applet_key: key, title: value.title, data: value.data
    }))
    this.appletResultsDataTarget.value = results.length ? JSON.stringify(results) : ""
  }

  // Submit when there is anything to send (typed text, images, or a buffered
  // applet result). Used by both the send button and applet auto-send.
  maybeSubmit() {
    if (this.busy) return
    if (this.contentFieldTarget.value.trim() !== '' || this.images.length > 0 || this.appletResults.size > 0) {
      this.element.requestSubmit()
      this.setBusyState(true)
    }
  }

  submit(e) {
    e.preventDefault();
    this.maybeSubmit()
  }

  // Student-facing summary for the chip: prefer the applet's own `summary`
  // sentence, otherwise fall back to a compact key/value line.
  summarizeAppletData(data) {
    if (data == null) return ""
    if (typeof data !== "object") return String(data)
    if (typeof data.summary === "string" && data.summary.trim()) return data.summary.trim().slice(0, 400)
    if (Array.isArray(data)) return `${data.length} item${data.length === 1 ? "" : "s"}`
    return Object.entries(data)
      .slice(0, 4)
      .map(([k, v]) => `${k}: ${typeof v === "object" ? JSON.stringify(v) : v}`)
      .join(" · ")
      .slice(0, 160)
  }

  escapeHtml(value) {
    const div = document.createElement("div")
    div.textContent = String(value ?? "")
    return div.innerHTML
  }

  paste(event) {
    if (this.busy) return

    //console.log("Pasting image")
    const items = (event.clipboardData || event.originalEvent.clipboardData).items;
    for (const item of items) {
      if (item.type.indexOf("image") === 0) {
        if (!this.canAddMoreImages()) return
        if (!["image/png", "image/jpeg", "image/webp"].includes(item.type)) {
          alert("Invalid image type. Only PNG, JPEG, and WebP are allowed.")
          return
        }
        const file = item.getAsFile()
        this.addImage(file)
        event.preventDefault()
      }
    }
  }

  disconnect() {
    if (this.imagesMenuTarget && this.boundHandleMenuSelect) {
      this.imagesMenuTarget.removeEventListener('sl-select', this.boundHandleMenuSelect)
    }
    window.removeEventListener("applet:result", this.boundReceiveAppletResult)
    document.removeEventListener("llm-completion-finished", this.boundHandleCompletionFinished)
    document.removeEventListener("llm-completion-error", this.boundHandleCompletionError)
    this.element.removeEventListener("turbo:submit-end", this.boundHandleSubmitEnd)
  }

  handleSubmitEnd(event) {
    if (event.detail?.success === false) {
      this.setBusyState(false)
      return
    }
    // Sent successfully: clear any buffered applet results so they aren't resent.
    if (this.appletResults.size > 0) {
      this.appletResults.clear()
      this.updateAppletResultsData()
      this.updatePreview()
    }
  }

  handleCompletionFinished(event) {
    if (!this.eventMatchesConversation(event)) return

    if (event.detail?.tool_call_pending) {
      this.setBusyState(true)
      return
    }

    this.setBusyState(false)
  }

  handleCompletionError(event) {
    if (!this.eventMatchesConversation(event)) return
    this.setBusyState(false)
  }

  eventMatchesConversation(event) {
    if (!this.hasConversationIdValue) return true

    const conversationId = this.conversationIdValue.toString()
    const detailConversationId = event.detail?.conversation_id?.toString()
    if (detailConversationId && detailConversationId === conversationId) return true

    const targetId = event?.target?.id
    return targetId === this.conversationDomId()
  }

  conversationDomId() {
    return `conversation_${this.conversationIdValue}`
  }

  detectBusyFromDom() {
    if (!this.hasConversationIdValue) return false

    const conversationElement = document.getElementById(this.conversationDomId())
    return conversationElement?.querySelector("#new_message") != null
  }

  busyRegistry() {
    if (!window.__goaConversationBusyRegistry) {
      window.__goaConversationBusyRegistry = new Map()
    }
    return window.__goaConversationBusyRegistry
  }

  currentBusyState() {
    if (!this.hasConversationIdValue) return false
    return this.busyRegistry().get(this.conversationIdValue.toString()) === true
  }

  setBusyState(busy) {
    const nextState = Boolean(busy)
    this.busy = nextState

    if (this.hasConversationIdValue) {
      this.busyRegistry().set(this.conversationIdValue.toString(), nextState)
      this.dispatch("busy-change", {
        bubbles: true,
        detail: {
          busy: nextState,
          conversationId: this.conversationIdValue.toString()
        }
      })
    }

    this.applyBusyState(nextState)
  }

  applyBusyState(isBusy) {
    this.busy = Boolean(isBusy)

    if (this.hasContentFieldTarget) {
      const audioOnly = this.audioSettingValue === "only"
      this.contentFieldTarget.disabled = audioOnly
      this.contentFieldTarget.readOnly = !audioOnly && this.busy
    }

    if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = this.busy
    if (this.hasImagesMenuButtonTarget) this.imagesMenuButtonTarget.disabled = this.busy

    if (this.busy) {
      if (this.hasSubmitIconTarget) this.submitIconTarget.classList.add("hidden")
      if (this.hasSubmitSpinnerTarget) this.submitSpinnerTarget.classList.remove("hidden")
      if (this.hasImagesMenuButtonTarget) this.imagesMenuButtonTarget.classList.add("hidden")
      return
    }

    if (this.hasSubmitSpinnerTarget) this.submitSpinnerTarget.classList.add("hidden")
    if (this.hasImagesMenuButtonTarget) this.imagesMenuButtonTarget.classList.remove("hidden")
    this.toggleSubmitButton()
  }
}
