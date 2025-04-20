import { Controller } from "@hotwired/stimulus"

// Usage: data-controller="llm-checkbox" on the form or checkbox
//        data-action="change->llm-checkbox#submit"
export default class extends Controller {
  submit(event) {
    // Find the closest form and submit it
    const form = event.target.form || this.element.closest("form");
    if (form) form.requestSubmit();
  }
}
