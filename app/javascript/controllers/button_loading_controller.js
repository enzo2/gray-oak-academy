import { Controller } from "@hotwired/stimulus"

// Shows a spinner on submit and restores the button after the request finishes.
// Attach to a form element with data-controller="button-loading".

export default class extends Controller {
  connect() {
    this.boundStartLoading = this.startLoading.bind(this);
    this.boundStopLoading = this.stopLoading.bind(this);
    this.element.addEventListener("turbo:submit-start", this.boundStartLoading);
    this.element.addEventListener("turbo:submit-end", this.boundStopLoading);
    this.element.addEventListener("turbo:submit-error", this.boundStopLoading);
  }

  disconnect() {
    this.element.removeEventListener("turbo:submit-start", this.boundStartLoading);
    this.element.removeEventListener("turbo:submit-end", this.boundStopLoading);
    this.element.removeEventListener("turbo:submit-error", this.boundStopLoading);
  }

  startLoading(event) {
    const button = this.element.querySelector("button[type='submit']");
    if (button) {
      button.disabled = true;
    }
  }

  stopLoading(event) {
    // If the request was successful (2xx), we assume the server either
    // redirected or replaced the button with a new state (e.g. "Generating...").
    // In these cases, we want to keep the button disabled/replaced.
    if (event.detail && event.detail.success) {
      return;
    }

    // If the request failed (e.g. 422 validation error, 500 server error),
    // we must re-enable the button so the user can try again.
    const button = this.element.querySelector("button[type='submit']");
    if (button) {
      button.disabled = false;
    }
  }

  boundStartLoading = null;
  boundStopLoading = null;
}
