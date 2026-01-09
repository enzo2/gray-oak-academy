import { Controller } from "@hotwired/stimulus";

/**
 * Sidebar controller (desktop <details> + mobile overlay).
 *
 * This controller exists because we want ONE sidebar DOM tree (one <nav>) that can appear in
 * two locations:
 * - Desktop: inside the persistent sidebar column (<details>).
 * - Mobile: inside an overlay panel.
 *
 * Key idea: singleton <nav> (move, don't clone)
 * - The sidebar contains elements with stable IDs that Turbo Streams target (e.g. conversation
 *   sidebar links). If we clone the sidebar for mobile + desktop, we create duplicate IDs.
 * - To avoid that, we create the sidebar markup once from a <template> and then *move* the same
 *   <nav> element between desktop and mobile containers.
 *
 * Elements and their roles:
 * - `contentTemplate` (<template>): blueprint for the sidebar markup; should contain exactly one
 *   root <nav> element.
 * - singleton `<nav data-sidebar-singleton="true">`: the live sidebar markup created from the
 *   template; this is the node we move around.
 * - `desktopSidebar` (<details>): desktop-only container that can be collapsed; its `open` state is
 *   persisted to localStorage under `data-sidebar-storage-key-value`.
 * - `desktopContent` (div): where the <nav> lives on desktop (inside the <details> column).
 * - `mobileSidebar` (div): the overlay wrapper that is shown/hidden.
 * - `sharedContent` (div): where the <nav> lives when the mobile overlay is open.
 * - `mobileBackdrop` / `mobilePanel`: optional targets used for the open/close transition animation.
 *
 * Lifecycle:
 * - `connect` and `turbo:render` call `ensureContent()`:
 *   - `ensureSingletonContent()` clones the <template> once (if needed) and stamps the nav as the singleton.
 *   - `placeSingletonContent()` moves the nav into desktop or mobile depending on whether the overlay is open.
 *
 * Close button behavior (required):
 * - The close/collapse button inside the template nav must be tagged with `data-sidebar-close-button="true"`.
 * - When the nav is moved into the mobile overlay, we temporarily rewrite that button to use
 *   `click->sidebar#closeMobile`, and restore the desktop attributes when moved back.
 *
 * Usage (required markup):
 * - Full tree example (minimal; classes/markup inside <nav> are up to the view):
 *
 *     <div
 *       data-controller="sidebar"
 *       data-action="sidebar:open-mobile@window->sidebar#openMobile"
 *       data-sidebar-storage-key-value="chatSidebar"
 *     >
 *       <!-- Mobile overlay -->
 *       <div data-sidebar-target="mobileSidebar" class="hidden">
 *         <div data-sidebar-target="mobileBackdrop" data-action="click->sidebar#closeMobile"></div>
 *         <div data-sidebar-target="mobilePanel">
 *           <div data-sidebar-target="sharedContent"></div>
 *         </div>
 *       </div>
 *
 *       <!-- Desktop sidebar column -->
 *       <details data-sidebar-target="desktopSidebar">
 *         <summary>…</summary>
 *
 *         <!-- Where the singleton <nav> lives on desktop -->
 *         <div data-sidebar-target="desktopContent">
 *           <!-- Blueprint: cloned once into a singleton <nav>, then moved as needed -->
 *           <template data-sidebar-target="contentTemplate">
 *             <nav>
 *               <button data-sidebar-close-button="true" data-action="click->sidebar#close">…</button>
 *               …
 *             </nav>
 *           </template>
 *         </div>
 *       </details>
 *     </div>
 *
 * - Required targets (names must match): `desktopSidebar`, `desktopContent`, `contentTemplate`,
 *   `mobileSidebar`, `sharedContent` (optionally `mobileBackdrop`, `mobilePanel`).
 * - Trigger mobile open from anywhere: `window.dispatchEvent(new CustomEvent("sidebar:open-mobile"))`.
 */

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
    // disconnecting Stimulus controllers; re-ensure/re-place the singleton nav after render.
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

    this.ensureSingletonContent();
    this.placeSingletonContent();
  }

  ensureSingletonContent() {
    if (!this.hasDesktopContentTarget) return;
    if (this.singletonNav()) return;

    const clone = this.contentTemplateTarget.content.cloneNode(true);
    const nav = clone.querySelector("nav");
    if (nav) nav.dataset.sidebarSingleton = "true";
    this.desktopContentTarget.appendChild(clone);
  }

  singletonNav() {
    return this.element.querySelector('nav[data-sidebar-singleton="true"]');
  }

  mobileSidebarOpen() {
    return this.hasMobileSidebarTarget && !this.mobileSidebarTarget.classList.contains("hidden");
  }

  placeSingletonContent() {
    const nav = this.singletonNav();
    if (!nav) return;

    if (this.mobileSidebarOpen()) {
      this.moveSingletonContentToMobile(nav);
    } else {
      this.moveSingletonContentToDesktop(nav);
    }
  }

  moveSingletonContentToDesktop(nav = this.singletonNav()) {
    if (!nav) return;
    if (!this.hasDesktopContentTarget) return;
    if (nav.parentElement !== this.desktopContentTarget) {
      this.desktopContentTarget.appendChild(nav);
    }
    this.configureNavForDesktop(nav);
  }

  moveSingletonContentToMobile(nav = this.singletonNav()) {
    if (!nav) return;
    if (!this.hasSharedContentTarget) return;
    if (nav.parentElement !== this.sharedContentTarget) {
      this.sharedContentTarget.appendChild(nav);
    }
    this.configureNavForMobile(nav);
  }

  sidebarCloseButton(nav) {
    return nav.querySelector('[data-sidebar-close-button="true"]');
  }

  configureNavForMobile(nav) {
    const closeButton = this.sidebarCloseButton(nav);
    if (!closeButton) return;

    if (!closeButton.dataset.sidebarDesktopAction) {
      closeButton.dataset.sidebarDesktopAction = closeButton.getAttribute("data-action") || "";
    }
    if (!closeButton.dataset.sidebarDesktopClass) {
      closeButton.dataset.sidebarDesktopClass = closeButton.className;
    }
    if (!closeButton.dataset.sidebarDesktopAriaLabel) {
      closeButton.dataset.sidebarDesktopAriaLabel = closeButton.getAttribute("aria-label") || "";
    }

    const svg = closeButton.querySelector("svg");
    if (svg && !svg.dataset.sidebarDesktopSvg) {
      svg.dataset.sidebarDesktopSvg = svg.innerHTML;
    }

    const slIcon = closeButton.querySelector("sl-icon");
    if (slIcon && !slIcon.dataset.sidebarDesktopName) {
      slIcon.dataset.sidebarDesktopName = slIcon.getAttribute("name") || "";
    }

    closeButton.setAttribute("data-action", "click->sidebar#closeMobile");
    closeButton.classList.remove("cursor-w-resize");
    closeButton.setAttribute("aria-label", "Close sidebar");

    if (svg) {
      svg.innerHTML =
        '<g fill="none" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" stroke="currentColor"><line x1="13.25" y1="4.75" x2="4.75" y2="13.25"></line><line x1="13.25" y1="13.25" x2="4.75" y2="4.75"></line></g>';
    }

    if (slIcon) {
      slIcon.setAttribute("name", "x-lg");
    }
  }

  configureNavForDesktop(nav) {
    const closeButton = this.sidebarCloseButton(nav);
    if (!closeButton) return;

    if (closeButton.dataset.sidebarDesktopAction) {
      closeButton.setAttribute("data-action", closeButton.dataset.sidebarDesktopAction);
    }
    if (closeButton.dataset.sidebarDesktopClass) {
      closeButton.className = closeButton.dataset.sidebarDesktopClass;
    }
    if (closeButton.dataset.sidebarDesktopAriaLabel) {
      closeButton.setAttribute("aria-label", closeButton.dataset.sidebarDesktopAriaLabel);
    }

    const svg = closeButton.querySelector("svg");
    if (svg && svg.dataset.sidebarDesktopSvg) {
      svg.innerHTML = svg.dataset.sidebarDesktopSvg;
    }

    const slIcon = closeButton.querySelector("sl-icon");
    if (slIcon && slIcon.dataset.sidebarDesktopName) {
      slIcon.setAttribute("name", slIcon.dataset.sidebarDesktopName);
    }
  }

  handleToggle(event) {
    // Save the current state to localStorage
    localStorage.setItem(this.storageKeyValue, this.desktopSidebarTarget.open.toString());
  }

  open() {
    this.ensureContent();
    this.moveSingletonContentToDesktop();
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
    this.ensureContent();
    this.moveSingletonContentToDesktop();
    if (this.hasDesktopSidebarTarget) {
      this.desktopSidebarTarget.open = !this.desktopSidebarTarget.open;
    }
  }

  openMobile() {
    this.ensureContent();
    this.moveSingletonContentToMobile();
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
          this.moveSingletonContentToDesktop();
        }
      }, 300); // Match the transition duration
    }
  }
}
