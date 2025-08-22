import { Controller } from "@hotwired/stimulus";

/*
  Collapsible controller
  - Expects:
      data-controller="collapsible" on a common ancestor
      data-collapsible-target="button" on the toggle button (e.g., sl-icon-button)
      data-collapsible-target="panel" on the collapsible content element
  - Behavior:
      - Toggles 'hidden' class on the panel (mobile-first)
      - Updates aria-expanded on the button
      - Switches chevron icon between down/up if using Shoelace icon-button
*/
export default class extends Controller {
  static targets = ["panel", "button"];

  connect() {
    // Initialize expanded state based on current visibility.
    // If the panel has 'hidden', treat as collapsed on mobile.
    const expanded = !this.panelTarget.classList.contains("hidden");
    this.setExpanded(expanded);
  }

  toggle() {
    const willExpand = this.panelTarget.classList.contains("hidden");
    this.panelTarget.classList.toggle("hidden");
    this.setExpanded(willExpand);
  }

  setExpanded(expanded) {
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", String(expanded));
      // If using Shoelace sl-icon-button, flip icon between down/up
      try {
        // Some environments may not expose 'name' property; guard it.
        if (expanded) {
          this.buttonTarget.name = "chevron-up";
        } else {
          this.buttonTarget.name = "chevron-down";
        }
      } catch (e) {
        // no-op
      }
    }
  }
}
