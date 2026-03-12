import { Controller } from "@hotwired/stimulus";

// This controller handles add/remove/rearrange content fields in course and lesson plan forms
// <template> tag is used to clone the field content
export default class extends Controller {
  static targets = ["fieldContainer", "lockState", "lockOverlay", "lockMessage"];

  connect() {
    this.boundTurboRender = () => this.syncUi();
    this.boundFormSubmit = (event) => this.preventSubmitWhenLocked(event);
    document.addEventListener("turbo:render", this.boundTurboRender);
    document.addEventListener("turbo:load", this.boundTurboRender);
    document.addEventListener("turbo:after-stream-render", this.boundTurboRender);
    this.formElement?.addEventListener("submit", this.boundFormSubmit);
    this.initialFormSignature = this.formSignature(this.formElement);

    this.syncUi();
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.boundTurboRender);
    document.removeEventListener("turbo:load", this.boundTurboRender);
    document.removeEventListener("turbo:after-stream-render", this.boundTurboRender);
    this.formElement?.removeEventListener("submit", this.boundFormSubmit);

    if (this.resizeFrame) {
      cancelAnimationFrame(this.resizeFrame);
      this.resizeFrame = null;
    }
  }

  autoResize(event) {
    this.resizeTextarea(event.target);
  }

  scheduleAutoResizeAll() {
    if (this.resizeFrame) {
      cancelAnimationFrame(this.resizeFrame);
    }

    this.resizeFrame = requestAnimationFrame(() => {
      this.resizeFrame = null;
      this.autoResizeAll();
      this.syncLockState();
    });
  }

  syncUi() {
    this.updateArrowVisibility();
    this.scheduleAutoResizeAll();
    this.syncLockState();
  }

  autoResizeAll() {
    this.fieldContainerTarget.querySelectorAll('textarea').forEach(ta => this.resizeTextarea(ta));
  }

  resizeTextarea(textarea) {
    if (this.usesNativeFieldSizing(textarea)) { return; }
    textarea.style.height = 'auto';
    textarea.style.height = textarea.scrollHeight + 'px';
  }

  usesNativeFieldSizing(textarea) {
    return textarea.classList.contains('outline-native-autosize') &&
      window.CSS?.supports?.('field-sizing', 'content');
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
    this.scheduleAutoResizeAll();
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

  syncLockState() {
    const locked = this.isLocked;
    const lockMessage = this.hasLockStateTarget ? this.lockStateTarget.dataset.lockMessage || "" : "";

    if (this.hasLockMessageTarget) {
      this.lockMessageTarget.textContent = lockMessage;
    }

    if (this.hasLockOverlayTarget) {
      this.lockOverlayTarget.classList.toggle("hidden", !locked);
      this.lockOverlayTarget.setAttribute("aria-hidden", locked ? "false" : "true");
    }

    const activeElement = document.activeElement;
    if (locked && activeElement instanceof HTMLElement && this.fieldContainerTarget.contains(activeElement)) {
      activeElement.blur();
    }

    this.fieldContainerTarget.setAttribute("aria-busy", locked ? "true" : "false");

    this.lockManagedControls.forEach((element) => {
      if (locked) {
        if (!element.dataset.outlineLockInitialDisabled) {
          element.dataset.outlineLockInitialDisabled = element.disabled ? "true" : "false";
        }
        element.disabled = true;
      } else {
        const initiallyDisabled = element.dataset.outlineLockInitialDisabled === "true";
        element.disabled = initiallyDisabled;
        delete element.dataset.outlineLockInitialDisabled;
      }
    });
  }

  get lockManagedControls() {
    if (!this.formElement || !this.hasLockStateTarget) { return []; }

    return Array.from(
      new Set(
        this.formElement.querySelectorAll(
          "input:not([type='hidden']), textarea, select, button, sl-button, sl-icon-button"
        )
      )
    );
  }

  get formElement() {
    return this.fieldContainerTarget.closest("form");
  }

  get isLocked() {
    return this.hasLockStateTarget && this.lockStateTarget.dataset.locked === "true";
  }

  preventSubmitWhenLocked(event) {
    if (!this.isLocked) { return; }

    event.preventDefault();
    event.stopPropagation();
  }

  guardResearchStart(event) {
    const form = event.target;
    if (!(form instanceof HTMLFormElement)) { return; }
    if (form.dataset.outlineResearchStart !== "true") { return; }
    if (!this.formElement) { return; }
    if (this.formSignature(this.formElement) === this.initialFormSignature) { return; }

    event.preventDefault();
    event.stopPropagation();
    window.alert(form.dataset.outlineDirtyMessage || "Save or discard your edits before continuing.");
  }

  formSignature(form) {
    if (!form) { return ""; }

    return Array.from(form.querySelectorAll("input, textarea, select")).map((field) => {
      const type = field.type || field.tagName.toLowerCase();
      const name = field.name || "";

      if (field.tagName === "SELECT") {
        const value = Array.from(field.options)
          .filter((option) => option.selected)
          .map((option) => option.value)
          .join("\u0001");

        return `${name}\u0000${type}\u0000${value}`;
      }

      if (type === "checkbox" || type === "radio") {
        return `${name}\u0000${type}\u0000${field.checked ? "1" : "0"}\u0000${field.value}`;
      }

      return `${name}\u0000${type}\u0000${field.value}`;
    }).join("\u0002");
  }
}
