import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="sidebar"
export default class extends Controller {
  static targets = [
    "desktopSidebar",
    "mobileSidebar",
    "contentTemplate",
    "sharedContent",
    "desktopContent",
    "mobileBackdrop",
    "mobilePanel",
  ];
  static values = {
    storageKey: { type: String, default: "sidebarOpen" },
  };

  initialize() {
    this.boundHandleToggle = this.handleToggle.bind(this);
    this.boundEnsureContent = this.ensureContent.bind(this);
  }

  connect() {
    this.ensureContent();

    if (this.hasDesktopSidebarTarget) {
      // Temporarily disable transitions to prevent animation on page load
      this.desktopSidebarTarget.style.transition = "none";

      // Restore the saved state from localStorage, default to open if no saved state
      const savedState = localStorage.getItem(this.storageKeyValue);

      if (savedState !== null) {
        this.desktopSidebarTarget.open = savedState === "true";
      } else {
        // Default to open for first-time visitors
        this.desktopSidebarTarget.open = true;
      }

      // Re-enable transitions after a brief delay
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          this.desktopSidebarTarget.style.transition = "";
        });
      });

      // Listen for toggle events to save the state
      this.desktopSidebarTarget.addEventListener("toggle", this.boundHandleToggle);
    }

    // Turbo "morph" / refresh can remove JS-inserted sidebar content without
    // disconnecting Stimulus controllers; re-ensure cloned content after render.
    document.addEventListener("turbo:render", this.boundEnsureContent);
  }

  disconnect() {
    if (this.hasDesktopSidebarTarget && this.boundHandleToggle) {
      this.desktopSidebarTarget.removeEventListener("toggle", this.boundHandleToggle);
    }

    document.removeEventListener("turbo:render", this.boundEnsureContent);
  }

  ensureContent() {
    if (!this.hasContentTemplateTarget) return;

    this.ensureDesktopContent();
    this.ensureMobileContent();
  }

  ensureDesktopContent() {
    if (!this.hasDesktopContentTarget) return;
    if (this.desktopContentTarget.querySelector('[data-sidebar-clone="desktop"]')) return;

    const desktopClone = this.contentTemplateTarget.content.cloneNode(true);
    const desktopNav = desktopClone.querySelector("nav");
    if (desktopNav) desktopNav.dataset.sidebarClone = "desktop";
    this.desktopContentTarget.appendChild(desktopClone);
  }

  ensureMobileContent() {
    if (!this.hasSharedContentTarget) return;
    if (this.sharedContentTarget.querySelector('[data-sidebar-clone="mobile"]')) return;

    const mobileClone = this.contentTemplateTarget.content.cloneNode(true);
    const mobileNav = mobileClone.querySelector("nav");
    if (mobileNav) {
      mobileNav.dataset.sidebarClone = "mobile";

      const closeButton = mobileNav.querySelector('[data-action*="sidebar#close"]');
      if (closeButton) {
        closeButton.setAttribute("data-action", "click->sidebar#closeMobile");
        closeButton.classList.remove("cursor-w-resize");
        closeButton.setAttribute("aria-label", "Close sidebar");

        const svg = closeButton.querySelector("svg");
        if (svg) {
          svg.innerHTML =
            '<g fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" stroke="currentColor"><line x1="13.25" y1="4.75" x2="4.75" y2="13.25"></line><line x1="13.25" y1="13.25" x2="4.75" y2="4.75"></line></g>';
        }
      }
    }

    this.sharedContentTarget.appendChild(mobileClone);
  }

  handleToggle(event) {
    // Save the current state to localStorage
    localStorage.setItem(this.storageKeyValue, this.desktopSidebarTarget.open.toString());
  }

  open() {
    this.ensureDesktopContent();
    if (this.hasDesktopSidebarTarget) {
      this.desktopSidebarTarget.open = true;
    }
  }

  close() {
    if (this.hasDesktopSidebarTarget) {
      this.desktopSidebarTarget.open = false;
    }
  }

  toggle() {
    this.ensureDesktopContent();
    if (this.hasDesktopSidebarTarget) {
      this.desktopSidebarTarget.open = !this.desktopSidebarTarget.open;
    }
  }

  openMobile() {
    this.ensureMobileContent();
    if (this.hasMobileSidebarTarget) {
      // Set initial hidden states
      if (this.hasMobileBackdropTarget) {
        this.mobileBackdropTarget.style.opacity = "0";
      }
      if (this.hasMobilePanelTarget) {
        this.mobilePanelTarget.style.transform = "translateX(-100%)";
      }

      // Remove hidden class
      this.mobileSidebarTarget.classList.remove("hidden");

      // Trigger transition on next frame
      requestAnimationFrame(() => {
        if (this.hasMobileBackdropTarget) {
          this.mobileBackdropTarget.style.opacity = "1";
        }
        if (this.hasMobilePanelTarget) {
          this.mobilePanelTarget.style.transform = "translateX(0)";
        }
      });
    }
  }

  closeMobile() {
    if (this.hasMobileSidebarTarget) {
      // Trigger closing transition
      if (this.hasMobileBackdropTarget) {
        this.mobileBackdropTarget.style.opacity = "0";
      }
      if (this.hasMobilePanelTarget) {
        this.mobilePanelTarget.style.transform = "translateX(-100%)";
      }

      // Wait for transition to complete before hiding
      setTimeout(() => {
        if (this.hasMobileSidebarTarget) {
          this.mobileSidebarTarget.classList.add("hidden");
        }
      }, 300); // Match the transition duration
    }
  }
}
