import { Controller } from "@hotwired/stimulus";

/*
  Collapsible controller
  - Expects:
      data-controller="collapsible" on a common ancestor
      data-collapsible-target="button" on the toggle button (e.g., sl-icon-button or button)
      data-action="click->collapsible#toggle" on the button or its wrapper
      data-collapsible-target="panel" on the collapsible content element
  
  - Optional Targets:
      data-collapsible-target="fade" (for read-more style gradients)
  
  - Values:
      collapsedClass: (String, default: "hidden") - The class to toggle for collapsed state
      moreText: (String) - Text to show when collapsed (e.g. "Show More")
      lessText: (String) - Text to show when expanded (e.g. "Show Less")
      checkOverflow: (Boolean, default: false) - If true, checks if content overflows height and hides button if not
  
  - Behavior:
      - Toggles 'collapsedClass' on the panel
      - Updates aria-expanded on the button
      - Switches chevron icon between down/up if using Shoelace icon-button
      - Updates button text if moreText/lessText provided
      - Hides/shows button and fade based on overflow if checkOverflow is true
*/
export default class extends Controller {
  static targets = ["panel", "button", "fade"];
  static values = {
    collapsedClass: { type: String, default: "hidden" },
    moreText: { type: String, default: "" },
    lessText: { type: String, default: "" },
    checkOverflow: { type: Boolean, default: false }
  };

  connect() {
    // Initialize expanded state based on current class presence.
    const isCollapsed = this.panelTarget.classList.contains(this.collapsedClassValue);
    this.setExpanded(!isCollapsed);

    if (this.checkOverflowValue) {
      this.checkOverflow();
      this.resizeObserver = new ResizeObserver(() => this.checkOverflow());
      this.resizeObserver.observe(this.panelTarget);
    }
  }

  disconnect() {
    if (this.resizeObserver) {
      this.resizeObserver.disconnect();
    }
  }

  toggle(event) {
    if (event) event.preventDefault();
    
    const wasCollapsed = this.panelTarget.classList.contains(this.collapsedClassValue);
    this.panelTarget.classList.toggle(this.collapsedClassValue);
    
    const expanded = wasCollapsed; // toggled state
    this.setExpanded(expanded);
    
    if (this.checkOverflowValue) {
      // Force check immediately to ensure UI state is consistent
      this.checkOverflow();
    }
  }

  setExpanded(expanded) {
    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", String(expanded));
      
      // Handle Shoelace sl-icon-button (flip icon)
      try {
        if (this.buttonTarget.tagName.toLowerCase().includes('icon')) {
            this.buttonTarget.name = expanded ? "chevron-up" : "chevron-down";
        }
      } catch (e) { /* no-op */ }

      // Handle Text Updates (Show More / Show Less)
      if (this.moreTextValue && this.lessTextValue) {
        this.buttonTarget.innerText = expanded ? this.lessTextValue : this.moreTextValue;
      }
    }

    // Handle Fade visibility (hide when expanded)
    // If we rely on overflow check, that will handle re-showing it when collapsed.
    // But we should definitely hide it when expanded.
    if (this.hasFadeTarget) {
      if (expanded) {
        this.fadeTarget.classList.add("hidden");
      } else if (!this.checkOverflowValue) {
        // If not using overflow check, assume we should show fade when collapsed (if target exists)
        this.fadeTarget.classList.remove("hidden");
      } else {
        // If using overflow check, let checkOverflow() handle the 'remove hidden' logic for fade
        // But we can trigger it here just in case
        this.checkOverflow();
      }
    }
  }

  checkOverflow() {
    const isCollapsed = this.panelTarget.classList.contains(this.collapsedClassValue);

    if (!isCollapsed) {
      // Expanded state:
      // Always show button (so user can collapse again)
      if (this.hasButtonTarget) this.buttonTarget.classList.remove("hidden");
      // Always hide fade
      if (this.hasFadeTarget) this.fadeTarget.classList.add("hidden");
      return;
    }

    // Collapsed state: Check for overflow
    // We add a small buffer (1px) to avoid precision issues
    const isOverflowing = this.panelTarget.scrollHeight > (this.panelTarget.clientHeight + 1);

    if (this.hasButtonTarget) {
      this.buttonTarget.classList.toggle("hidden", !isOverflowing);
    }

    if (this.hasFadeTarget) {
      this.fadeTarget.classList.toggle("hidden", !isOverflowing);
    }
  }
}
