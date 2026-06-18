import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["closeButton", "customGuidanceSection", "customGuidanceInput", "contentSnapshot"]

  connect() {
    this.syncCustomGuidance()
  }

  presetChanged() {
    this.syncCustomGuidance()
  }

  // Copy the current outline (in the separate lesson plan form) into hidden
  // inputs on the revise form so a revision operates on unsaved edits too.
  // Runs on form submit, before Turbo serializes the request.
  snapshotContent() {
    if (!this.hasContentSnapshotTarget) return

    const host = this.contentSnapshotTarget
    host.replaceChildren()

    this.contentSnapshotFields().forEach(({ name, value }) => {
      host.appendChild(this.hiddenField(name, value))
    })
  }

  appendContentSnapshot(event) {
    if (!this.hasContentSnapshotTarget || !event.formData) return
    if (event.formData.has("lesson_plan[content_snapshot]")) return

    this.contentSnapshotFields().forEach(({ name, value }) => {
      event.formData.append(name, value)
    })
  }

  contentSnapshotFields() {
    const outline = document.getElementById("lesson-plan-form")
    if (!outline) return []

    const fields = [{ name: "lesson_plan[content_snapshot]", value: "1" }]
    const keyFields = outline.querySelectorAll('input[name="lesson_plan[content_keys][]"]')
    const valueFields = outline.querySelectorAll('textarea[name="lesson_plan[content_values][]"]')

    keyFields.forEach((keyField, index) => {
      fields.push({ name: "lesson_plan[content_keys][]", value: keyField.value })
      fields.push({ name: "lesson_plan[content_values][]", value: valueFields[index]?.value ?? "" })
    })

    return fields
  }

  hiddenField(name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    return input
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
