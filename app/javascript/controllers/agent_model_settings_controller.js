import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { modelsPath: String, statusPath: String, providerUriMap: Object }
  static targets = [ "providerSelect", "modelCombobox", "status" ]

  connect() {
    this.refreshModelSource(false)
    this.refreshStatus()
  }

  updateModels() {
    this.refreshModelSource(true)
    window.requestAnimationFrame(() => this.refreshStatus())
  }

  modelChanged(event) {
    this.refreshStatus(event)
  }

  refreshModelSource(clearOnChange) {
    if (!this.hasProviderSelectTarget || !this.hasModelComboboxTarget) return

    const providerId = this.providerSelectTarget.value.toString()
    const apiUri = (this.providerUriMapValue && this.providerUriMapValue[providerId]) || ""
    const newUrl = `${this.modelsPathValue}?api_uri=${encodeURIComponent(apiUri)}`

    const comboboxController = this.application.getControllerForElementAndIdentifier(
      this.modelComboboxTarget,
      "hw-combobox"
    )
    if (!comboboxController) return

    const srcChanged = comboboxController.asyncSrcValue !== newUrl
    if (srcChanged) {
      comboboxController.asyncSrcValue = newUrl
      if (clearOnChange) comboboxController.clear()
    }
  }

  refreshStatus(event = null) {
    if (!this.hasProviderSelectTarget || !this.hasStatusTarget || !this.hasStatusPathValue) return

    const providerId = this.providerSelectTarget.value.toString()
    const model = this.modelValue(event)
    const params = new URLSearchParams({ provider_id: providerId, model: model })
    const requestId = (this.statusRequestId || 0) + 1
    this.statusRequestId = requestId

    fetch(`${this.statusPathValue}?${params.toString()}`, {
      headers: { Accept: "application/json" }
    })
      .then((response) => (response.ok ? response.json() : Promise.reject(response)))
      .then((payload) => {
        if (this.statusRequestId !== requestId) return
        this.renderStatus(payload)
      })
      .catch(() => {
        if (this.statusRequestId !== requestId) return
        this.statusTarget.innerHTML = `
          Runs are only enabled when this field is set and the selected provider has a shared key. Use a strongly agentic model with reliable tool use and structured output support.
        `
      })
  }

  renderStatus(payload) {
    const parts = [
      "Runs are only enabled when this field is set and the selected provider has a shared key. Use a strongly agentic model with reliable tool use and structured output support."
    ]

    if (payload.provider_key_present) {
      parts.push(`<span class="text-success-600 dark:text-success-400">Shared provider key is configured.</span>`)
    } else {
      parts.push(`<span class="text-danger-600 dark:text-danger-400">Add a shared key for the selected provider in LLM APIs to enable this pipeline.</span>`)
    }

    if (payload.openrouter && payload.model_present) {
      if (payload.context_length) {
        parts.push(`
          <span class="block text-success-600 dark:text-success-400 mt-1">
            Context metadata found: ${this.formatNumber(payload.context_length)} tokens. Stateless OpenRouter runs will stop near 80% reported input-token usage.
          </span>
        `)
      } else {
        parts.push(`
          <span class="block text-warning-700 dark:text-warning-300 mt-1">
            No local context metadata found for this OpenRouter agent model. Try adding the model first in LLM API settings.
          </span>
        `)
      }
    }

    this.statusTarget.innerHTML = parts.join(" ")
  }

  modelValue(event = null) {
    if (event?.type === "hw-combobox:selection") return event.detail?.value || ""
    if (event?.type === "hw-combobox:clear") return ""
    if (event?.type === "input" && typeof event.target?.value === "string") return event.target.value

    const comboboxController = this.application.getControllerForElementAndIdentifier(
      this.modelComboboxTarget,
      "hw-combobox"
    )
    if (comboboxController?.hasHiddenFieldTarget) return comboboxController.hiddenFieldTarget.value

    const field = this.modelComboboxTarget.querySelector("input[name], input[type=hidden]")
    return field?.value || this.modelComboboxTarget.value || ""
  }

  formatNumber(value) {
    return new Intl.NumberFormat().format(Number(value))
  }
}
