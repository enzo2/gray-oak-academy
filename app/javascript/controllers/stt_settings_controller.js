import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "providerSelect",
    "methodSelect",
    "speechWrapper",
    "chatWrapper",
    "speechInput",
    "chatInput",
    "ttsModelCombobox",
    "ttsVoiceCombobox",
    "speechModelCombobox",
    "sharedTokenHint",
    "sharedTokenProviderName"
  ]
  static values = {
    speechModelsPath: String,
    speechVoicesPath: String,
    providerUriMap: Object,
    providerLabelMap: Object,
    providerTokenMap: Object
  }

  connect() {
    // Ensure targets exist before attempting to update UI
    if (this.hasMethodSelectTarget) this.update()
    this.refreshSpeechModelSources(false)
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

  providerChanged() {
    this.refreshSpeechModelSources(true)
    this.refreshSharedTokenHint()
  }

  ttsModelChanged() {
    window.requestAnimationFrame(() => this.refreshVoiceSource(true))
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

  refreshSpeechModelSources(clearOnChange) {
    if (!this.hasProviderSelectTarget || !this.hasSpeechModelsPathValue) return

    const providerId = this.providerSelectTarget.value.toString()
    const apiUri = (this.providerUriMapValue && this.providerUriMapValue[providerId]) || ""

    this.updateComboboxSource(this.ttsModelComboboxTargetIfPresent(), "tts", apiUri, clearOnChange)
    this.updateComboboxSource(this.speechModelComboboxTargetIfPresent(), "stt", apiUri, clearOnChange)
    this.refreshVoiceSource(clearOnChange)
    this.refreshSharedTokenHint()
  }

  updateComboboxSource(targetElement, kind, apiUri, clearOnChange) {
    if (!targetElement) return

    const newUrl = `${this.speechModelsPathValue}?kind=${encodeURIComponent(kind)}&api_uri=${encodeURIComponent(apiUri)}`
    const comboboxController = this.application.getControllerForElementAndIdentifier(targetElement, "hw-combobox")
    if (!comboboxController) return

    const srcChanged = comboboxController.asyncSrcValue !== newUrl
    if (srcChanged) {
      comboboxController.asyncSrcValue = newUrl
      if (clearOnChange) comboboxController.clear()
    }
  }

  ttsModelComboboxTargetIfPresent() {
    return this.hasTtsModelComboboxTarget ? this.ttsModelComboboxTarget : null
  }

  speechModelComboboxTargetIfPresent() {
    return this.hasSpeechModelComboboxTarget ? this.speechModelComboboxTarget : null
  }

  refreshVoiceSource(clearOnChange) {
    if (!this.hasProviderSelectTarget || !this.hasTtsVoiceComboboxTarget || !this.hasSpeechVoicesPathValue) return

    const providerId = this.providerSelectTarget.value.toString()
    const apiUri = (this.providerUriMapValue && this.providerUriMapValue[providerId]) || ""
    const model = this.comboboxValue(this.ttsModelComboboxTargetIfPresent())
    const newUrl = `${this.speechVoicesPathValue}?api_uri=${encodeURIComponent(apiUri)}&model=${encodeURIComponent(model)}`
    const comboboxController = this.application.getControllerForElementAndIdentifier(
      this.ttsVoiceComboboxTarget,
      "hw-combobox"
    )
    if (!comboboxController) return

    const srcChanged = comboboxController.asyncSrcValue !== newUrl
    if (srcChanged) {
      comboboxController.asyncSrcValue = newUrl
      if (clearOnChange) comboboxController.clear()
    }
  }

  comboboxValue(targetElement) {
    if (!targetElement) return ""

    const comboboxController = this.application.getControllerForElementAndIdentifier(targetElement, "hw-combobox")
    if (comboboxController?.hasHiddenFieldTarget) return comboboxController.hiddenFieldTarget.value

    const field = targetElement.querySelector("input[name], input[type='hidden']")
    return field?.value || targetElement.value || ""
  }

  refreshSharedTokenHint() {
    if (!this.hasProviderSelectTarget || !this.hasSharedTokenHintTarget) return

    const providerId = this.providerSelectTarget.value.toString()
    const hasSharedToken = Boolean(this.providerTokenMapValue && this.providerTokenMapValue[providerId])
    const providerLabel = (this.providerLabelMapValue && this.providerLabelMapValue[providerId]) || "provider"

    if (this.hasSharedTokenProviderNameTarget) {
      this.sharedTokenProviderNameTarget.textContent = providerLabel
    }

    this.sharedTokenHintTarget.classList.toggle("hidden", !hasSharedToken)
  }
}
