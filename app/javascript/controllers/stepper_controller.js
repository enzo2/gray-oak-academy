import { Controller } from "@hotwired/stimulus"

// Generic, nestable stepper for multi-section forms/workflows.
//
// Usage:
// - Attach `data-controller="stepper"` to a wrapper element.
// - Mark each panel with `data-stepper-target="step"`.
// - Mark each clickable step item with `data-stepper-target="indicator"`
//   and `data-step-index="N"`, wiring clicks to `stepper#go`.
// - Optional previous/next controls use `data-stepper-target="prevButton"`
//   and `data-stepper-target="nextButton"` with `stepper#prev`/`stepper#next`.
//
// Nesting:
// - Multiple steppers can be nested; each instance scopes to its own targets.
// - The parent workflow and child steppers (for per-item navigation) do not
//   interfere with each other because Stimulus target resolution is local.
export default class extends Controller {
  static targets = ["step", "indicator", "prevButton", "nextButton", "statusText"]
  static values = {
    start: Number,
    variant: String
  }

  connect() {
    this.currentIndex = this.hasStartValue ? this.startValue : 0
    this.currentIndex = this.clamp(this.currentIndex)
    this.render({ initial: true })
  }

  next(event) {
    event.preventDefault()
    this.goTo(this.currentIndex + 1)
  }

  prev(event) {
    event.preventDefault()
    this.goTo(this.currentIndex - 1)
  }

  go(event) {
    event.preventDefault()
    const rawIndex = event.currentTarget.dataset.stepIndex
    const index = Number.parseInt(rawIndex, 10)
    if (Number.isNaN(index)) return

    this.goTo(index)
  }

  goTo(index) {
    if (this.stepTargets.length === 0) return

    this.currentIndex = this.clamp(index)
    this.render({ initial: false })
  }

  clamp(index) {
    const maxIndex = Math.max(this.stepTargets.length - 1, 0)
    return Math.min(Math.max(index, 0), maxIndex)
  }

  render({ initial = false } = {}) {
    const total = this.stepTargets.length
    if (total === 0) return

    this.element.dataset.stepperInitialized = "1"

    this.stepTargets.forEach((stepElement, index) => {
      const isActive = index === this.currentIndex
      stepElement.classList.toggle("hidden", !isActive)
      stepElement.setAttribute("aria-hidden", (!isActive).toString())
    })

    this.indicatorTargets.forEach((indicatorElement, index) => {
      const state = this.indicatorState(index)
      indicatorElement.dataset.state = state
      indicatorElement.classList.toggle("is-active", state === "active")
      indicatorElement.classList.toggle("is-complete", state === "complete")
      indicatorElement.classList.toggle("is-upcoming", state === "upcoming")

      if (state === "active") {
        indicatorElement.setAttribute("aria-current", "step")
      } else {
        indicatorElement.removeAttribute("aria-current")
      }
    })

    this.prevButtonTargets.forEach((button) => {
      button.disabled = this.currentIndex === 0
    })

    this.nextButtonTargets.forEach((button) => {
      button.disabled = this.currentIndex >= total - 1
    })

    this.statusTextTargets.forEach((el) => {
      el.textContent = `Question ${this.currentIndex + 1} of ${total}`
    })

    this.dispatch("change", { detail: { index: this.currentIndex, total: total, initial: initial } })
  }

  indicatorState(index) {
    if (index < this.currentIndex) return "complete"
    if (index === this.currentIndex) return "active"
    return "upcoming"
  }
}
