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
    const field = document.createElement("div");
    field.classList.add("flex", "mb-2", "space-x-2");
    field.innerHTML = `
      <input type="text" name="course[outline_keys][]" placeholder="Topic" class="form-input w-1/4" required />
      <input type="text" name="course[outline_values][]" placeholder="Details" class="form-input w-3/4" required />
      <sl-icon-button name="x-circle" class="remove-field p-2" data-action="click->outline#removeField"></sl-icon-button>
    `;
    event.target.parentElement.insertBefore(field, event.target);
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