import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { modelsPath: String }
  static targets = [ "modelCombobox" ] // This should target the fieldset/div of the *second* combobox

  connect() {
    console.log("LLM Settings controller connected");
    // Optional: If the URI field might be pre-filled on page load,
    // you might want to trigger an initial update.
    // const initialUri = this.element.querySelector('input[role="combobox"]')?.value;
    // if (initialUri) {
    //   this.updateModels({ target: { value: initialUri }, type: 'connect' }); // Simulate event
    // }
  }

  /**
   * Updates the async source URL for the model combobox based on the selected API URI.
   * Handles different event types that trigger this update.
   */
  updateModels(event) {
    console.log("updateModels triggered by event:", event.type, event);
    let apiUri = ""; // Default to empty

    // --- Determine the API URI based on the event type ---
    if (event.type === 'hw-combobox:clear') {
      // If the source combobox was cleared
      apiUri = "";
      console.log("Source cleared, API URI set to empty");
    } else if (event.detail && typeof event.detail.display !== 'undefined') {
      // For hw-combobox custom events (like hw-combobox:selection)
      // Use event.detail.display, which contains the text visible in the input
      apiUri = event.detail.display || ""; // Use display value, fallback to empty
      console.log(`Event type: ${event.type}, API URI from detail.display:`, apiUri);
    } else if (event.target && typeof event.target.value !== 'undefined') {
       // For standard events like 'input' originating from the text input
      apiUri = event.target.value || ""; // Use the input's current value
      console.log(`Event type: ${event.type}, API URI from target.value:`, apiUri);
    } else if (event.type === 'connect' && event.target?.value) {
       // Handling the simulated event from connect()
       apiUri = event.target.value || "";
       console.log(`Event type: ${event.type}, API URI from initial value:`, apiUri);
    }
     else {
      console.warn("Could not determine API URI from event:", event);
      // Don't proceed if we couldn't get a URI
      // Optionally clear the dependent combobox here as well
      this.clearModelCombobox();
      return;
    }
    // --- End API URI Determination ---

    if (!this.hasModelComboboxTarget) {
      console.error("Could not find modelCombobox target");
      return;
    }

    // Get the Stimulus controller instance for the target combobox
    const modelComboboxElement = this.modelComboboxTarget;
    const modelComboboxController = this.application.getControllerForElementAndIdentifier(modelComboboxElement, "hw-combobox");

    if (!modelComboboxController) {
      console.error("Could not find hw-combobox controller instance on the modelCombobox target.");
      return;
    }

    // Construct the new URL for the model combobox's options
    const newUrl = `${this.modelsPathValue}?api_uri=${encodeURIComponent(apiUri)}`;

    // --- Update the target combobox using its controller ---
    // Set the asyncSrcValue - this tells hw-combobox where to load from next time
    modelComboboxController.asyncSrcValue = newUrl;

    // Clear the target combobox's current value and input display
    this.clearModelCombobox(modelComboboxController);

    console.log("Updated model combobox asyncSrcValue to:", newUrl);
  }

  /**
   * Helper to clear the model combobox using its controller instance.
   */
  clearModelCombobox(controller = null) {
      if (!this.hasModelComboboxTarget) return;

      const modelComboboxController = controller || this.application.getControllerForElementAndIdentifier(this.modelComboboxTarget, "hw-combobox");

      if (modelComboboxController) {
          modelComboboxController.clear(); // Use the clear method from hw-combobox
          console.log("Cleared model combobox");
      } else {
          console.error("Could not find hw-combobox controller to clear model combobox.");
          // Fallback for safety, though less ideal:
          // const input = this.modelComboboxTarget.querySelector('input[role="combobox"]');
          // const hiddenInput = this.modelComboboxTarget.querySelector('input[type="hidden"]');
          // if (input) input.value = "";
          // if (hiddenInput) hiddenInput.value = "";
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

    console.log("Model selection event:", event.type, "Model:", modelName, "Is new?", isNew);

    if (isNew) {
      // Make sure this alert doesn't block execution if not needed,
      // or consider a less intrusive notification.
      alert(`You've entered a new model name ('${modelName}'). Please ensure it works correctly and save it if needed.`);
    }
  }
}