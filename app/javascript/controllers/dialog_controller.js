import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // Closes the dialog
  hide() {
    this.element.hide()
  }

  // Handles turbo:submit-end event
  // Usage: data-action="turbo:submit-end->dialog#submitEnd"
  submitEnd(event) {
    if (event.detail.success) {
      this.hide()
      // Find the form within the dialog and reset it
      const form = this.element.querySelector('form')
      if (form) {
        form.reset()
      }
    }
  }
}
