import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "menu"]

  connect() {
    this.isOpen = false
    this.handleDocumentClick = this.handleDocumentClick.bind(this)
    this.handleDocumentKeydown = this.handleDocumentKeydown.bind(this)
    document.addEventListener("click", this.handleDocumentClick)
    document.addEventListener("keydown", this.handleDocumentKeydown)
    this.close()
  }

  disconnect() {
    document.removeEventListener("click", this.handleDocumentClick)
    document.removeEventListener("keydown", this.handleDocumentKeydown)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()

    if (this.isOpen) {
      this.close()
    } else {
      this.open()
    }
  }

  open() {
    this.isOpen = true
    this.menuTarget.classList.remove("hidden")
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.isOpen = false
    if (this.hasMenuTarget) this.menuTarget.classList.add("hidden")
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  handleDocumentClick(event) {
    if (!this.isOpen) return
    if (this.element.contains(event.target)) return
    this.close()
  }

  handleDocumentKeydown(event) {
    if (!this.isOpen) return
    if (event.key !== "Escape") return
    this.close()
    this.triggerTarget?.focus()
  }
}
