import { Controller } from "@hotwired/stimulus"

// Adds 'loading' attribute to shoelace submit button when form submitted
export default class extends Controller {
  connect() {
    this.element.addEventListener("turbo:submit-start", this.startLoading);
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.startLoading);
  }

  startLoading = (event) => {
    const button = this.element.querySelector("sl-button[type='submit']");
    if (button) {
      button.setAttribute("loading", "");
    }
  }
}