// For auto-saving checkboxes. Submits the form upon toggle.

import { Controller } from "@hotwired/stimulus"

// Usage: data-controller="auto-submit-toggle" on the form or checkbox
//        data-action="auto-submit-toggle#submit"

export default class extends Controller {
  submit(event) {
    // Find the closest form and submit it
    const form = event.target.closest("form")
    if (form) form.requestSubmit()
  }
}
