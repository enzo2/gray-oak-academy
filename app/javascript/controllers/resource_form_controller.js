import { Controller } from "@hotwired/stimulus"

const TYPES = [ "file", "url", "applet", "other" ]

export default class extends Controller {
  static targets = [ "typeSelect", "categoryInput", "urlSection", "fileSection", "appletSection", "otherSection" ]
  static values = {
    initialType: String,
    payloadLocked: Boolean
  }

  connect() {
    this.applyType(this.initialTypeValue || "other")
    if (!this.payloadLockedValue && (this.initialTypeValue || "other") === "other") this.applyCategorySuggestion()
  }

  changeType(event) {
    this.applyType(event.target.value)
  }

  categoryChanged() {
    if (this.payloadLockedValue) return
    this.applyCategorySuggestion()
  }

  applyCategorySuggestion() {
    const suggestedType = this.suggestedTypeFromCategory(this.currentCategoryValue())
    if (!suggestedType) return
    this.applyType(suggestedType)
  }

  suggestedTypeFromCategory(categoryValue) {
    if (!categoryValue) return null
    if (categoryValue.includes("applet")) return "applet"
    if (categoryValue.includes("file") || categoryValue.includes("pdf")) return "file"
    if (categoryValue.includes("web") || categoryValue.includes("site")) return "url"
    return null
  }

  currentCategoryValue() {
    const candidates = []
    if (this.hasCategoryInputTarget) candidates.push(this.categoryInputTarget)
    const modelCategoryInput = this.element.querySelector("#resource_category, [name='resource[category]']")
    if (modelCategoryInput) candidates.push(modelCategoryInput)

    for (const candidate of candidates) {
      if (!candidate) continue
      if (typeof candidate.value === "string" && candidate.value.trim() !== "") return candidate.value.trim().toLowerCase()

      const nestedInput = candidate.querySelector("input, select, textarea")
      if (nestedInput && typeof nestedInput.value === "string" && nestedInput.value.trim() !== "") {
        return nestedInput.value.trim().toLowerCase()
      }
    }

    return ""
  }

  applyType(type) {
    const normalizedType = TYPES.includes(type) ? type : "other"
    if (this.hasTypeSelectTarget) this.typeSelectTarget.value = normalizedType

    if (this.hasUrlSectionTarget) this.toggleSection(this.urlSectionTarget, normalizedType === "url", false)
    if (this.hasFileSectionTarget) this.toggleSection(this.fileSectionTarget, normalizedType === "file", true)
    if (this.hasAppletSectionTarget) this.toggleSection(this.appletSectionTarget, normalizedType === "applet", true)
    if (this.hasOtherSectionTarget) this.toggleSection(this.otherSectionTarget, normalizedType === "other", false)

    if (normalizedType !== "url") this.clearUrlValue()
  }

  toggleSection(section, active, disableInputs) {
    section.classList.toggle("hidden", !active)
    if (!disableInputs) return
    section.querySelectorAll("input, textarea, select").forEach((field) => {
      field.disabled = !active
    })
  }

  clearUrlValue() {
    if (!this.hasUrlSectionTarget) return
    const urlInput = this.urlSectionTarget.querySelector("input[type='url'], input[name='resource[uri]']")
    if (urlInput) urlInput.value = ""
  }
}
