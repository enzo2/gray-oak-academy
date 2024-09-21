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
    event.target.parentElement.remove();
  }

  moveUp(event) {
    event.preventDefault();
    const field = event.target.closest('.flex');
    if (field.previousElementSibling && field.previousElementSibling !== this.fieldContainerTarget.querySelector('template')) {
      this.fieldContainerTarget.insertBefore(field, field.previousElementSibling);
    }
  }

  moveDown(event) {
    event.preventDefault();
    const field = event.target.closest('.flex');
    if (field.nextElementSibling) {
      this.fieldContainerTarget.insertBefore(field.nextElementSibling, field);
    }
  }
}