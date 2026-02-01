import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "video",
    "preview",
    "canvas",
    "captureButton",
    "retakeButton",
    "useButton",
    "status",
    "switchButton",
    "mirrorButton"
  ]

  static values = {
    modalId: String
  }

  connect() {
    this.availabilityRunning = false
    this.lastAvailabilityCheck = 0
    this.userMirrorOverride = false
    this.mirrorPreferencePrefix = "goa.camera.mirror"
    this.savedMirrorPreference = null
    this.cameraAvailable = false
    this.initializeAvailability()
  }

  async initializeAvailability() {
    if (this.availabilityRunning) return
    const now = Date.now()
    if (now - this.lastAvailabilityCheck < 400) return
    this.lastAvailabilityCheck = now

    this.availabilityRunning = true
    this.cameraAvailable = false
    this.dispatch("availability", { detail: { available: false } })

    if (!this.hasEssentialTargets()) {
      this.availabilityRunning = false
      return
    }
    if (!window.isSecureContext) {
      this.availabilityRunning = false
      return
    }
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      this.availabilityRunning = false
      return
    }
    if (!navigator.mediaDevices.enumerateDevices) {
      this.availabilityRunning = false
      return
    }

    try {
      const devices = await navigator.mediaDevices.enumerateDevices()
      this.videoDevices = devices.filter(d => d.kind === "videoinput")
      if (this.videoDevices.length > 0) {
        this.cameraAvailable = true
        this.updateSwitchButtonVisibility()
        this.dispatch("availability", { detail: { available: true } })
      }
    } catch (error) {
      console.warn("Failed to enumerate video devices.", error)
    } finally {
      this.availabilityRunning = false
    }
  }

  open(event) {
    if (event && event.preventDefault) event.preventDefault()
    if (!this.cameraAvailable || !this.hasEssentialTargets()) return
    const modalController = this.modalController()
    if (!modalController) return
    modalController.open()
  }

  handleModalOpen(event) {
    if (!this.isOurModalEvent(event)) return
    this.resetCameraState()
    this.startCamera()
  }

  handleModalClose(event) {
    if (!this.isOurModalEvent(event)) return
    this.stopCamera()
    this.resetCameraState()
  }

  resetCameraState() {
    if (!this.hasEssentialTargets()) return
    if (this.cameraPreviewUrl) {
      URL.revokeObjectURL(this.cameraPreviewUrl)
      this.cameraPreviewUrl = null
    }
    this.capturedCameraFile = null
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = ""
    }
    this.previewTarget.classList.add("hidden")
    this.videoTarget.classList.remove("hidden")
    this.captureButtonTarget.classList.remove("hidden")
    this.captureButtonTarget.disabled = true
    this.retakeButtonTarget.classList.add("hidden")
    this.useButtonTarget.classList.add("hidden")
  }

  async startCamera() {
    if (!this.hasEssentialTargets()) return
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      alert("Camera access is not supported in this browser.")
      this.modalController()?.close()
      return
    }

    try {
      if (this.hasStatusTarget) {
        this.statusTarget.textContent = "Requesting camera access..."
      }
      const constraints = this.currentDeviceId
        ? { video: { deviceId: { exact: this.currentDeviceId } }, audio: false }
        : { video: true, audio: false }
      this.cameraStream = await navigator.mediaDevices.getUserMedia(constraints)
      this.videoTarget.srcObject = this.cameraStream
      await this.videoTarget.play()
      await this.updateVideoDevices()
      this.syncCurrentDeviceId()
      this.loadMirrorPreference()
      this.applyMirrorDefaults()
      this.applyMirrorState()
      this.captureButtonTarget.disabled = false
      if (this.hasStatusTarget) {
        this.statusTarget.textContent = ""
      }
    } catch (err) {
      console.error("Error accessing camera:", err)
      const message = (err && err.name === "NotAllowedError")
        ? "Camera access was denied. Please allow camera permissions for this site in your browser settings."
        : "Could not access the camera. Please try again."
      alert(message)
      this.modalController()?.close()
    }
  }

  stopCamera() {
    if (this.cameraStream) {
      this.cameraStream.getTracks().forEach(track => track.stop())
      this.cameraStream = null
    }
    if (this.hasVideoTarget) {
      this.videoTarget.pause()
      this.videoTarget.srcObject = null
    }
  }

  captureCamera() {
    if (!this.cameraStream) return
    if (!this.hasEssentialTargets()) return

    const width = this.videoTarget.videoWidth || 1280
    const height = this.videoTarget.videoHeight || 720

    this.canvasTarget.width = width
    this.canvasTarget.height = height
    const context = this.canvasTarget.getContext("2d")
    if (!context) {
      alert("Could not capture the photo. Please try again.")
      return
    }
    context.save()
    if (this.isMirrored) {
      context.translate(width, 0)
      context.scale(-1, 1)
    }
    context.drawImage(this.videoTarget, 0, 0, width, height)
    context.restore()

    this.canvasTarget.toBlob((blob) => {
      if (!blob) {
        alert("Could not capture the photo. Please try again.")
        return
      }
      this.capturedCameraFile = new File([blob], `camera-${Date.now()}.jpg`, { type: blob.type || "image/jpeg" })
      if (this.cameraPreviewUrl) {
        URL.revokeObjectURL(this.cameraPreviewUrl)
      }
      this.cameraPreviewUrl = URL.createObjectURL(blob)
      this.previewTarget.src = this.cameraPreviewUrl
      this.previewTarget.classList.remove("hidden")
      this.videoTarget.classList.add("hidden")
      this.captureButtonTarget.classList.add("hidden")
      this.retakeButtonTarget.classList.remove("hidden")
      this.useButtonTarget.classList.remove("hidden")
    }, "image/jpeg", 0.92)
  }

  retakeCamera() {
    if (!this.hasEssentialTargets()) return
    if (this.cameraPreviewUrl) {
      URL.revokeObjectURL(this.cameraPreviewUrl)
      this.cameraPreviewUrl = null
    }
    this.capturedCameraFile = null
    this.previewTarget.classList.add("hidden")
    this.videoTarget.classList.remove("hidden")
    this.captureButtonTarget.classList.remove("hidden")
    this.retakeButtonTarget.classList.add("hidden")
    this.useButtonTarget.classList.add("hidden")

    if (!this.cameraStream) {
      this.startCamera()
    }
  }

  useCameraPhoto() {
    if (!this.capturedCameraFile) return
    this.dispatch("photo", { detail: { file: this.capturedCameraFile } })
    this.modalController()?.close()
  }

  async updateVideoDevices() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return
    try {
      const devices = await navigator.mediaDevices.enumerateDevices()
      this.videoDevices = devices.filter(d => d.kind === "videoinput")
      this.updateSwitchButtonVisibility()
    } catch (error) {
      console.warn("Failed to enumerate video devices.", error)
    }
  }

  updateSwitchButtonVisibility() {
    if (!this.hasSwitchButtonTarget) return
    const hasMultiple = (this.videoDevices || []).length > 1
    this.switchButtonTarget.classList.toggle("hidden", !hasMultiple)
  }

  syncCurrentDeviceId() {
    if (!this.cameraStream) return
    const track = this.cameraStream.getVideoTracks()[0]
    if (!track) return
    const settings = track.getSettings()
    if (settings?.deviceId) {
      this.currentDeviceId = settings.deviceId
    }
  }

  applyMirrorDefaults() {
    if (this.userMirrorOverride) return
    if (this.savedMirrorPreference !== null && this.savedMirrorPreference !== undefined) {
      this.isMirrored = this.savedMirrorPreference
      return
    }
    const track = this.cameraStream?.getVideoTracks()[0]
    const settings = track?.getSettings() || {}
    let shouldMirror = true

    if (settings.facingMode === "environment") {
      shouldMirror = false
    } else if (settings.facingMode === "user") {
      shouldMirror = true
    }

    const device = (this.videoDevices || []).find(d => d.deviceId === settings.deviceId)
    if (device?.label) {
      const label = device.label.toLowerCase()
      if (label.includes("back") || label.includes("rear") || label.includes("environment")) {
        shouldMirror = false
      } else if (label.includes("front") || label.includes("user") || label.includes("facetime")) {
        shouldMirror = true
      }
    }

    this.isMirrored = shouldMirror
  }

  applyMirrorState() {
    if (!this.hasEssentialTargets()) return
    const transform = this.isMirrored ? "scaleX(-1)" : ""
    this.videoTarget.style.transform = transform
    this.previewTarget.style.transform = ""
    if (this.hasMirrorButtonTarget) {
      this.mirrorButtonTarget.setAttribute("aria-pressed", this.isMirrored ? "true" : "false")
    }
  }

  toggleMirror() {
    if (!this.previewTarget.classList.contains("hidden")) {
      this.retakeCamera()
    }
    this.userMirrorOverride = true
    this.isMirrored = !this.isMirrored
    this.saveMirrorPreference(this.isMirrored)
    this.applyMirrorState()
  }

  async switchCamera() {
    if (!this.hasEssentialTargets()) return
    if (!this.videoDevices || this.videoDevices.length < 2) return

    if (!this.previewTarget.classList.contains("hidden")) {
      this.retakeCamera()
    }

    const currentIndex = this.videoDevices.findIndex(d => d.deviceId === this.currentDeviceId)
    const nextIndex = currentIndex >= 0 ? (currentIndex + 1) % this.videoDevices.length : 0
    this.currentDeviceId = this.videoDevices[nextIndex].deviceId
    this.userMirrorOverride = false

    this.stopCamera()
    await this.startCamera()
  }

  hasEssentialTargets() {
    return this.hasVideoTarget &&
      this.hasPreviewTarget &&
      this.hasCanvasTarget &&
      this.hasCaptureButtonTarget &&
      this.hasRetakeButtonTarget &&
      this.hasUseButtonTarget
  }

  loadMirrorPreference() {
    try {
      const value = window.localStorage.getItem(this.mirrorPreferenceKey())
      if (value === "true") {
        this.savedMirrorPreference = true
      } else if (value === "false") {
        this.savedMirrorPreference = false
      } else {
        this.savedMirrorPreference = null
      }
    } catch (error) {
      this.savedMirrorPreference = null
    }
  }

  saveMirrorPreference(value) {
    try {
      window.localStorage.setItem(this.mirrorPreferenceKey(), value ? "true" : "false")
      this.savedMirrorPreference = value
    } catch (error) {
      // Ignore storage errors (private mode, quota, etc.)
    }
  }

  mirrorPreferenceKey() {
    if (this.currentDeviceId) {
      return `${this.mirrorPreferencePrefix}.${this.currentDeviceId}`
    }
    const track = this.cameraStream?.getVideoTracks?.()[0]
    const facingMode = track?.getSettings?.()?.facingMode
    if (facingMode) {
      return `${this.mirrorPreferencePrefix}.facing.${facingMode}`
    }
    return `${this.mirrorPreferencePrefix}.default`
  }

  modalController() {
    const modalElement = this.modalElement()
    if (!modalElement) return null
    return this.application.getControllerForElementAndIdentifier(modalElement, "modal")
  }

  modalElement() {
    if (!this.hasModalIdValue) return null
    return document.getElementById(this.modalIdValue)
  }

  isOurModalEvent(event) {
    const modalElement = this.modalElement()
    if (!modalElement || !event) return false
    return event.target === modalElement
  }

  disconnect() {
    if (this.cameraPreviewUrl) {
      URL.revokeObjectURL(this.cameraPreviewUrl)
      this.cameraPreviewUrl = null
    }
    this.stopCamera()
  }
}
