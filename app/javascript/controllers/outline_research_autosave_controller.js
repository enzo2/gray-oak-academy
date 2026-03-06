import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["unansweredCount", "resumeReadinessMeta", "resumeButton", "status"]
  static values = {
    url: String
  }

  connect() {
    this.saving = false
    this.pending = false
    this.initializedStepperElements = new WeakSet()
    this.seedInitializedSteppers()
  }

  handleStepperChange(event) {
    const source = event.target
    if (!(source instanceof HTMLElement)) return

    const initialChange = event.detail?.initial === true

    // Ignore each stepper instance's initial render event.
    if (!this.initializedStepperElements.has(source)) {
      this.initializedStepperElements.add(source)
      if (initialChange) return
    }

    this.enqueueSave()
  }

  enqueueSave() {
    if (this.saving) {
      this.pending = true
      return
    }

    this.saveProgress()
  }

  async saveProgress() {
    this.saving = true
    this.setStatus("saving", "Saving progress...")

    try {
      const response = await this.submitAutosave()
      const payload = await this.parseResponseBody(response)

      if (response.ok && payload.ok) {
        this.applyPayload(payload)
        this.setStatus("saved", "Progress saved.")
      } else {
        this.setStatus("error", payload.error || "Autosave failed. Changes are still on this page.")
      }
    } catch (_error) {
      this.setStatus("error", "Autosave failed. Changes are still on this page.")
    } finally {
      this.saving = false
      if (this.pending) {
        this.pending = false
        this.saveProgress()
      }
    }
  }

  submitAutosave() {
    const formData = new FormData(this.element)
    formData.set("autosave", "1")

    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
    const headers = {
      Accept: "application/json"
    }
    if (token) headers["X-CSRF-Token"] = token

    return fetch(this.urlValue || this.element.action, {
      method: "PATCH",
      body: formData,
      headers,
      credentials: "same-origin"
    })
  }

  async parseResponseBody(response) {
    try {
      return await response.json()
    } catch (_error) {
      return { ok: false, error: "Autosave returned an unexpected response." }
    }
  }

  applyPayload(payload) {
    this.unansweredCountTargets.forEach((target) => {
      target.textContent = `${payload.unanswered_count}`
    })

    const ready = payload.ready_to_resume === true
    const resumable = payload.resumable_run === true

    this.resumeReadinessMetaTargets.forEach((target) => {
      target.textContent = ready && resumable ? "Ready" : "Blocked"
    })

    if (this.hasResumeButtonTarget) {
      this.resumeButtonTarget.disabled = !(ready && resumable)
    }
  }

  seedInitializedSteppers() {
    this.markStepperIfInitialized(this.element)
    this.element.querySelectorAll('[data-controller~="stepper"]').forEach((element) => {
      this.markStepperIfInitialized(element)
    })
  }

  markStepperIfInitialized(element) {
    if (!(element instanceof HTMLElement)) return
    if (element.dataset.stepperInitialized !== "1") return

    this.initializedStepperElements.add(element)
  }

  setStatus(state, message) {
    if (!this.hasStatusTarget) return

    const stateClasses = {
      idle: ["text-stone-600", "dark:text-stone-300"],
      saving: ["text-stone-700", "dark:text-stone-200"],
      saved: ["text-success-700", "dark:text-success-300"],
      error: ["text-danger-700", "dark:text-danger-300"]
    }

    const allStateClasses = Object.values(stateClasses).flat()

    this.statusTarget.textContent = message
    this.statusTarget.classList.remove(...allStateClasses)

    const classesForState = stateClasses[state] || stateClasses.idle
    this.statusTarget.classList.add(...classesForState)
  }
}
