import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { modelsPath: String, supportedUris: Array, hasUserToken: Boolean, envBaseUri: String, envKeyPresent: Boolean }
  static targets = [ "modelCombobox", "reasoningModelCombobox", "sharedTokenHint", "tokenStatus", "statusPersonal", "statusShared", "statusEnv", "statusRequired", "tokenOverrideBtn", "tokenInputWrapper", "tokenInput" ]

  connect() {
    //console.log("LLM Settings controller connected");
    const hidden = document.getElementById("setting_llm_api_base_uri-hw-hidden-field");
    const initialUri = (hidden && typeof hidden.value === "string") ? hidden.value : "";
    this.updateTokenStatus(initialUri || "");
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
    this.updateTokenStatus(apiUri);

    const shouldClear = event.type !== 'initial';

    if (this.hasModelComboboxTarget) {
      this.updateComboboxSource(this.modelComboboxTarget, newUrl, shouldClear);
    }
    if (this.hasReasoningModelComboboxTarget) {
      this.updateComboboxSource(this.reasoningModelComboboxTarget, newUrl, shouldClear);
    }
  }

  /**
   * Updates a specific combobox target's async source and clears its value.
   * @param {HTMLElement} targetElement - The combobox element to update.
   * @param {string} newUrl - The new URL for the combobox's async source.
   */
  updateComboboxSource(targetElement, newUrl, shouldClear = true) {
    const comboboxController = this.application.getControllerForElementAndIdentifier(targetElement, "hw-combobox");

    if (comboboxController) {
      const prevUrl = comboboxController.asyncSrcValue;
      const srcChanged = prevUrl !== newUrl;

      if (srcChanged) {
        comboboxController.asyncSrcValue = newUrl;
        //console.log(`Updated ${targetElement.id} asyncSrcValue to: ${newUrl}`);
      }

      if (shouldClear && srcChanged) {
        comboboxController.clear();
        //console.log(`Cleared ${targetElement.id} due to source change`);
      }
    } else {
      console.warn(`Could not find hw-combobox controller for target:`, targetElement);
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

  /**
   * Update token status UI based on current selection and whether user has a personal token saved.
   * Logic:
   * - If user has a personal token, show "personal" and hide others.
   * - Else, if selected provider has shared token, show "shared".
   * - Else, show "env" (default).
   * Input field remains hidden + disabled until user clicks Override.
   */
  updateTokenStatus(apiUri) {
    const hasPersonal = !!this.hasUserTokenValue;

    const normalized = (apiUri || "").trim();
    const normalizedWithSlash = normalized.length > 0 && !normalized.endsWith("/") ? `${normalized}/` : normalized;
    const hasSharedForProvider = (this.supportedUrisValue || []).includes(normalizedWithSlash);

    // ENV provider applicability:
    const envBaseRaw = (this.envBaseUriValue || "").trim();
    const envBaseNormalized = envBaseRaw.length > 0 && !envBaseRaw.endsWith("/") ? `${envBaseRaw}/` : envBaseRaw;
    const usingEnvProvider = (normalizedWithSlash === "") || (envBaseNormalized && normalizedWithSlash === envBaseNormalized);

    // Status visibility
    if (this.hasStatusPersonalTarget) this.setHidden(this.statusPersonalTarget, !(hasPersonal));
    if (this.hasStatusSharedTarget) this.setHidden(this.statusSharedTarget, !( !hasPersonal && hasSharedForProvider ));
    if (this.hasStatusEnvTarget) this.setHidden(this.statusEnvTarget, !( !hasPersonal && !hasSharedForProvider && usingEnvProvider ));
    if (this.hasStatusRequiredTarget) this.setHidden(this.statusRequiredTarget, !( !hasPersonal && !hasSharedForProvider && !usingEnvProvider ));

    // Reset input hidden/disabled by default
    if (this.hasTokenInputWrapperTarget) {
      this.setHidden(this.tokenInputWrapperTarget, true);
    }
    if (this.hasTokenInputTarget) {
      this.tokenInputTarget.disabled = true;
      this.tokenInputTarget.value = "";
    }
    if (this.hasTokenOverrideBtnTarget) {
      this.tokenOverrideBtnTarget.textContent = "Override token";
    }

    // Auto-show input when a token is required (no personal, no shared, and not using ENV provider)
    const required = (!hasPersonal && !hasSharedForProvider && !usingEnvProvider);
    if (required && this.hasTokenInputWrapperTarget && this.hasTokenInputTarget && this.hasTokenOverrideBtnTarget) {
      this.tokenInputWrapperTarget.classList.remove("hidden");
      this.tokenInputTarget.disabled = false;
      this.tokenOverrideBtnTarget.textContent = "Cancel override";
    }
  }

  /**
   * Toggle token input visibility and enabled state.
   * - Visible + enabled means user intends to change/clear token (blank clears).
   * - Hidden + disabled means do not submit and do not change existing token.
   */
  showTokenInput() {
    if (!this.hasTokenInputWrapperTarget || !this.hasTokenInputTarget || !this.hasTokenOverrideBtnTarget) return;

    const isHidden = this.tokenInputWrapperTarget.classList.contains("hidden");
    if (isHidden) {
      this.tokenInputWrapperTarget.classList.remove("hidden");
      this.tokenInputTarget.disabled = false;
      this.tokenInputTarget.focus();
      this.tokenOverrideBtnTarget.textContent = "Cancel override";
    } else {
      this.tokenInputWrapperTarget.classList.add("hidden");
      this.tokenInputTarget.disabled = true;
      this.tokenInputTarget.value = "";
      this.tokenOverrideBtnTarget.textContent = "Override token";
    }
  }

  setHidden(el, hidden) {
    if (!el) return;
    if (hidden) {
      el.classList.add("hidden");
    } else {
      el.classList.remove("hidden");
    }
  }

}
