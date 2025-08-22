import { Controller } from "@hotwired/stimulus";

// Opens Shoelace drawer components
// Supports multiple drawers on a page
// Usage: Add data-controller="drawer" to a parent element
// Add data-drawer-target="drawer" to the shoelace drawer element
// Add data-drawer-id="unique-id" to the drawer element and the button that opens it
// Add data-action="click->drawer#openDrawer" to the element that will open the drawer
// 
// To use dialogs referenced within a drawer: 
// Add data-dialog-id to any sl-dialogs within the drawer, and their corresponding buttons
// Use showDialog on the button to open the dialog

export default class extends Controller {
  static targets = ["drawer", "openButton", "closeButton"];

  open(event) {
    const drawer = this.drawerTargets.find((d => d.dataset.drawerId === event.currentTarget.dataset.drawerId));
    if (!drawer) return;
    if (typeof drawer.show === "function") {
      drawer.show();
    } 
  }
  
  // Closes any open drawer, and opens the sl-dialog referenced by data-dialog-id on the clicked element
  showDialog(event) {
    const dialogId = event.currentTarget?.dataset?.dialogId || event.target?.dataset?.dialogId;
    let dialog = null;

    if (dialogId) {
      dialog = document.querySelector(`sl-dialog[data-dialog-id="${dialogId}"]`);
    }
    // Show the dialog after a short timeout so any menu closing animations complete
    if (dialog) {
      // Move dialog to body so it's visible even after menu/dropdown closes
      document.body.appendChild(dialog);

      // Hide the drawer
      this.drawerTargets.forEach((drawer) => {
        if (typeof drawer.hide === "function") drawer.hide();
      });

      setTimeout(() => { 
        dialog.show(); 
      }, 70);
    } else { console.warn("Dialog not found:", dialogId);  }
  }

}
