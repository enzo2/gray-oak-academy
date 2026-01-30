import { Controller } from "@hotwired/stimulus";

// This controller handles add/remove/rearrange content fields in course and lesson plan forms
// <template> tag is used to clone the field content
export default class extends Controller {
  static targets = ["fieldContainer"];

  connect() {
    this.updateArrowVisibility();
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
    this.updateArrowVisibility();
  }

  removeField(event) {
    event.preventDefault();
    const field = event.target.closest('.outline-field');
    if (!field) { return; }
    field.remove();
    this.updateArrowVisibility();
  }

  moveUp(event) {
    event.preventDefault();
    const field = event.target.closest('.outline-field');
    if (!field) { return; }
    if (field.previousElementSibling && field.previousElementSibling !== this.fieldContainerTarget.querySelector('template')) {
      this.fieldContainerTarget.insertBefore(field, field.previousElementSibling);
    }
    this.updateArrowVisibility();
  }

  moveDown(event) {
    event.preventDefault();
    const field = event.target.closest('.outline-field');
    if (!field) { return; }
    if (field.nextElementSibling) {
      this.fieldContainerTarget.insertBefore(field.nextElementSibling, field);
    }
    this.updateArrowVisibility();
  }

  updateArrowVisibility() {
    const fields = Array.from(this.fieldContainerTarget.querySelectorAll('.outline-field'));
    const setButtonHidden = (button, hidden) => {
      button.style.visibility = hidden ? 'hidden' : '';
      button.style.pointerEvents = hidden ? 'none' : '';
    };

    fields.forEach((field, index) => {
      const upButtons = field.querySelectorAll('.move-up');
      const downButtons = field.querySelectorAll('.move-down');

      if (index === 0) {
        upButtons.forEach(btn => setButtonHidden(btn, true));
      } else {
        upButtons.forEach(btn => setButtonHidden(btn, false));
      }

      if (index === fields.length - 1) {
        downButtons.forEach(btn => setButtonHidden(btn, true));
      } else {
        downButtons.forEach(btn => setButtonHidden(btn, false));
      }
    });

    if (fields.length === 1) {
      fields[0].querySelectorAll('.move-up, .move-down').forEach(btn => setButtonHidden(btn, true));
    }
  }
}
