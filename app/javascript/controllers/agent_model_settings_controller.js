import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { modelsPath: String, providerUriMap: Object }
  static targets = [ "providerSelect", "modelCombobox" ]

  connect() {
    this.refreshModelSource(false)
  }

  updateModels() {
    this.refreshModelSource(true)
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
}
