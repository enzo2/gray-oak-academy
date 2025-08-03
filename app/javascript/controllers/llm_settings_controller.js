import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { modelsPath: String }
  static targets = [ "modelCombobox", "reasoningModelCombobox" ] 

  connect() {
    //console.log("LLM Settings controller connected");
    // Optional: If the URI field might be pre-filled on page load,
    // you might want to trigger an initial update.
    // const initialUri = this.element.querySelector('input[role="combobox"]')?.value;
    // if (initialUri) {
    //   this.updateModels({ target: { value: initialUri }, type: 'connect' }); // Simulate event
    // }
  }

  /**
   * Updates the async source URL for the model comboboxes based on the selected API URI.
   * Handles different event types that trigger this update.
   */
  updateModels(event) {
    let apiUri = "";

    if (event.type === 'hw-combobox:clear') {
      apiUri = "";
    } else if (event.detail && typeof event.detail.display !== 'undefined') {
      apiUri = event.detail.display || "";
    } else if (event.target && typeof event.target.value !== 'undefined') {
      apiUri = event.target.value || "";
    } else if (event.type === 'connect' && event.target?.value) {
      apiUri = event.target.value || "";
    } else {
      console.warn("Could not determine API URI from event:", event);
      this.clearAllComboboxes();
      return;
    }

    const newUrl = `${this.modelsPathValue}?api_uri=${encodeURIComponent(apiUri)}`;

    if (this.hasModelComboboxTarget) {
      this.updateComboboxSource(this.modelComboboxTarget, newUrl);
    }
    if (this.hasReasoningModelComboboxTarget) {
      this.updateComboboxSource(this.reasoningModelComboboxTarget, newUrl);
    }
  }

  /**
   * Updates a specific combobox target's async source and clears its value.
   * @param {HTMLElement} targetElement - The combobox element to update.
   * @param {string} newUrl - The new URL for the combobox's async source.
   */
  updateComboboxSource(targetElement, newUrl) {
    const comboboxController = this.application.getControllerForElementAndIdentifier(targetElement, "hw-combobox");

    if (comboboxController) {
      comboboxController.asyncSrcValue = newUrl;
      comboboxController.clear();
      //console.log(`Updated ${targetElement.id} asyncSrcValue to: ${newUrl}`);
    } else {
      console.error(`Could not find hw-combobox controller for target:`, targetElement);
    }
  }

  /**
   * Helper to clear all dependent comboboxes.
   */
  clearAllComboboxes() {
    if (this.hasModelComboboxTarget) {
      const controller = this.application.getControllerForElementAndIdentifier(this.modelComboboxTarget, "hw-combobox");
      if (controller) controller.clear();
    }
    if (this.hasReasoningModelComboboxTarget) {
      const controller = this.application.getControllerForElementAndIdentifier(this.reasoningModelComboboxTarget, "hw-combobox");
      if (controller) controller.clear();
    }
  }


  /**
   * Checks if a newly entered model name is being selected.
   * Triggered by the 'hw-combobox:selection' event on the model combobox.
   */
  checkNewModel(event) {
    // Check the detail provided by the hw-combobox:selection event
    const isNew = event.detail?.isNewAndAllowed || false;
    const modelName = event.detail?.display || event.target?.value || "Unknown"; // Get display value

    //console.log("Model selection event:", event.type, "Model:", modelName, "Is new?", isNew);

    if (isNew) {
      // Make sure this alert doesn't block execution if not needed,
      // or consider a less intrusive notification.
      alert(`You've entered a new model name ('${modelName}'). Please ensure it works correctly and save it if needed.`);
    }
  }
}
