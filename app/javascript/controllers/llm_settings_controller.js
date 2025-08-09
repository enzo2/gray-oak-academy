import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { modelsPath: String, supportedUris: Array }
  static targets = [ "modelCombobox", "reasoningModelCombobox", "sharedTokenHint" ]

  connect() {
    //console.log("LLM Settings controller connected");
    const initialUri = document.getElementById("setting_llm_api_base_uri-hw-hidden-field").value
    if (initialUri) {
      this.updateModels({ detail: { value: initialUri }, type: 'initial' });
    }
  }

  /**
   * Updates the async source URL for the model comboboxes based on the selected API URI.
   * Handles different event types that trigger this update.
   */
  updateModels(event) {
    let apiUri = "";

    switch (event.type) {
      case 'hw-combobox:selection':
        // This event provides the clean value directly. This is the most reliable source.
        apiUri = event.detail.value || "";
        break;
      case 'hw-combobox:clear':
        // This event fires when the combobox is cleared.
        apiUri = "";
        break;
      case "initial":
        // This is a custom event type for initial load.
        apiUri = event.detail.value || "";
        break;
      default:
        // This handles the `input` event (user typing) and `connect`.
        // In these cases, we only have the visible display text, which may include the emoji.
        // We must clean it to get a valid URI.
        apiUri = (event.target.value || "").replace(/✅$/, '').trim();
        break;
    }

    const newUrl = `${this.modelsPathValue}?api_uri=${encodeURIComponent(apiUri)}`;
    this.toggleSharedTokenHint(apiUri);

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
      //console.log(`New URL for combobox ${targetElement.id}:`, newUrl);
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
   * Toggle the shared-token hint based on whether the selected URI is a SupportedApi
   */
  toggleSharedTokenHint(apiUri) {
    if (!this.hasSharedTokenHintTarget) return;

    const normalized = (apiUri || "").trim();
    // Ensure trailing slash for comparison consistency
    const normalizedWithSlash = normalized.length > 0 && !normalized.endsWith("/") ? `${normalized}/` : normalized;

    const supported = (this.supportedUrisValue || []).includes(normalizedWithSlash);

    if (supported) {
      this.sharedTokenHintTarget.classList.remove("hidden");
    } else {
      this.sharedTokenHintTarget.classList.add("hidden");
    }
  }

}
