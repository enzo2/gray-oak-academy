import { Controller } from "@hotwired/stimulus";

// This controller handles add/remove/rearrange content fields in course and lesson plan forms
// <template> tag is used to clone the field content
export default class extends Controller {
  static targets = ["fieldContainer"];

  connect() {
    this.updateArrowVisibility();
    this.autoResizeAll();
  }

  autoResize(event) {
    this.resizeTextarea(event.target);
  }

  autoResizeAll() {
    this.fieldContainerTarget.querySelectorAll('textarea').forEach(ta => this.resizeTextarea(ta));
  }

  resizeTextarea(textarea) {
    textarea.style.height = 'auto';
    textarea.style.height = textarea.scrollHeight + 'px';
  }

  get fieldsWrapper() {
    return this.fieldContainerTarget.querySelector('.outline-fields') || this.fieldContainerTarget;
  }

  addField(event) {
    event.preventDefault();
    const template = this.fieldContainerTarget.querySelector('template');
    if (!template) {
      console.error('Template not found in fieldContainer');
      return;
    }
    const fieldContent = template.content.cloneNode(true);
    this.fieldsWrapper.appendChild(fieldContent);
    this.updateArrowVisibility();
    this.autoResizeAll();
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
    const wrapper = this.fieldsWrapper;
    if (field.previousElementSibling) {
      wrapper.insertBefore(field, field.previousElementSibling);
    }
    this.updateArrowVisibility();
  }

  moveDown(event) {
    event.preventDefault();
    const field = event.target.closest('.outline-field');
    if (!field) { return; }
    if (field.nextElementSibling) {
      field.nextElementSibling.after(field);
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

      // Update section number indicator
      const numberEl = field.querySelector('.font-mono');
      if (numberEl) { numberEl.textContent = index + 1; }
    });

    if (fields.length === 1) {
      fields[0].querySelectorAll('.move-up, .move-down').forEach(btn => setButtonHidden(btn, true));
    }
  }
}
