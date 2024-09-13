import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="outline"
export default class extends Controller {
  static targets = ["fieldContainer"];

  initialize() {
  }

  connect() {
  }

  addField(event) {
    event.preventDefault();
    // Find the template within the fieldContainer
    const template = this.fieldContainerTarget.querySelector('template');
    if (!template) {
      console.error('Template not found in fieldContainer');
      return;
    }
    // Clone the template content
    const fieldContent = template.content.cloneNode(true);
    // Insert the field
    this.fieldContainerTarget.insertBefore(fieldContent, event.target);
  }

  removeField(event) {
    event.preventDefault();

    // Check the number of field divs in the container
    if (this.fieldContainerTarget.querySelectorAll('div').length > 1) {
      // Remove the field targeted by the remove button
      event.target.parentElement.remove();
    } else {
      // Clear the inputs if it's the only one left
      const inputs = event.target.closest('div').querySelectorAll('input');
      inputs.forEach(input => input.value = '');
    }
  }
}