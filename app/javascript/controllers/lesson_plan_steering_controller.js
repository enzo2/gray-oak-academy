import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["closeButton", "customGuidanceSection", "customGuidanceInput"]

  connect() {
    this.syncCustomGuidance()
  }

  presetChanged() {
    this.syncCustomGuidance()
  }

  submitEnd(event) {
    if (!event.detail.success) return

    if (this.generationQueued(event)) {
      this.closeButtonTargets[0]?.click()
      return
    }

    this.enableSubmitButton()

    requestAnimationFrame(() => {
      if (this.generationButtonDisabled()) {
        this.closeButtonTargets[0]?.click()
      }
    })
  }

  syncCustomGuidance() {
    const otherSelected = this.selectedPresetValue() === "other"

    this.customGuidanceSectionTarget.classList.toggle("hidden", !otherSelected)

    if (otherSelected) {
      this.customGuidanceInputTarget.disabled = false
      this.customGuidanceInputTarget.required = true
      this.customGuidanceInputTarget.focus()
    } else {
      this.customGuidanceInputTarget.required = false
      this.customGuidanceInputTarget.disabled = true
      this.customGuidanceInputTarget.value = ""
    }
  }

  selectedPresetValue() {
    return this.element.querySelector('input[name="preset"]:checked')?.value || "llm_decides"
  }

  generationQueued(event) {
    return this.fetchResponseHeader(event, "X-Lesson-Plan-Generation-Queued") === "true"
  }

  fetchResponseHeader(event, name) {
    return event.detail.fetchResponse?.header?.(name)
  }

  enableSubmitButton() {
    const submitButton = this.element.querySelector('button[type="submit"]')
    if (submitButton) submitButton.disabled = false
  }

  generationButtonDisabled() {
    return document.getElementById("generate-lesson-plan-button")?.disabled === true
  }
}
