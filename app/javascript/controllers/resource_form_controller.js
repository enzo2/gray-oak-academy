import { Controller } from "@hotwired/stimulus"

const TYPES = [ "file", "url", "video", "image", "applet", "text" ]

export default class extends Controller {
  static targets = [
    "typeSelect",
    "categoryInput",
    "urlSection",
    "fileSection",
    "appletSection",
    "textSection",
    "urlLabel",
    "urlEmbedHelp",
    "urlImageHelp",
    "embedDialogWrapper"
  ]
  static values = {
    initialType: String,
    payloadLocked: Boolean
  }

  connect() {
    const initialType = this.normalizedType(this.initialTypeValue)
    this.applyType(initialType)
    if (!this.payloadLockedValue && initialType === "text") this.applyCategorySuggestion()
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
    if (categoryValue.includes("video") || categoryValue.includes("youtube") || categoryValue.includes("vimeo")) return "video"
    if (categoryValue.includes("image") || categoryValue.includes("photo") || categoryValue.includes("diagram")) return "image"
    if (categoryValue.includes("quote") || categoryValue.includes("excerpt") || categoryValue.includes("text")) return "text"
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

  normalizedType(type) {
    return TYPES.includes(type) ? type : "text"
  }

  urlType(type) {
    return [ "url", "video", "image" ].includes(type)
  }

  applyType(type) {
    const normalizedType = this.normalizedType(type)
    if (this.hasTypeSelectTarget) this.typeSelectTarget.value = normalizedType

    if (this.hasUrlSectionTarget) this.toggleSection(this.urlSectionTarget, this.urlType(normalizedType), false)
    if (this.hasFileSectionTarget) this.toggleSection(this.fileSectionTarget, normalizedType === "file", true)
    if (this.hasAppletSectionTarget) this.toggleSection(this.appletSectionTarget, normalizedType === "applet", true)
    if (this.hasTextSectionTarget) this.toggleSection(this.textSectionTarget, normalizedType === "text", false)

    this.updateUrlUi(normalizedType)

    if (!this.urlType(normalizedType)) this.clearUrlValue()
    if (normalizedType !== "text") this.clearTextValue()
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

  clearTextValue() {
    if (!this.hasTextSectionTarget) return
    const textInput = this.textSectionTarget.querySelector("textarea[name='resource[content]'], textarea#resource_content")
    if (textInput) textInput.value = ""
  }

  updateUrlUi(normalizedType) {
    if (this.hasUrlLabelTarget) {
      if (normalizedType === "video") {
        this.urlLabelTarget.textContent = "Video URL"
      } else if (normalizedType === "image") {
        this.urlLabelTarget.textContent = "Image URL"
      } else {
        this.urlLabelTarget.textContent = "URL"
      }
    }

    const useEmbedChecker = [ "url", "video" ].includes(normalizedType)
    if (this.hasUrlEmbedHelpTarget) this.urlEmbedHelpTarget.classList.toggle("hidden", !useEmbedChecker)
    if (this.hasUrlImageHelpTarget) this.urlImageHelpTarget.classList.toggle("hidden", normalizedType !== "image")
    if (this.hasEmbedDialogWrapperTarget) this.embedDialogWrapperTarget.classList.toggle("hidden", !useEmbedChecker)
  }
}
