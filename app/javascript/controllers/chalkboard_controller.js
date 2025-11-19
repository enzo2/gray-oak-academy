import { Controller } from "@hotwired/stimulus"

// For future use, if can get it to work
//import * as htmlToImage from 'html-to-image';
//import { toJpeg, toBlob } from 'html-to-image';

export default class extends Controller {
  static targets = ["chalkboard", "container", "host", "screenshotDialog", "screenSizeWarning"]
  
  connect() {

    // Placeholders for moving the chalkboard DOM between desktop sidebar and mobile drawer
    this._originalParent = null;
    this._originalClasses = null;

    // If we found the container, cache original parent and classes immediately
    if (this.containerTarget) {
      this._originalParent = this.containerTarget.parentNode;
      this._originalClasses = this.containerTarget.className;
      //console.log("Chalkboard container found. Cached original parent and classes.");
    } else {
      console.warn("Chalkboard container (#chalkboard_container) not found on connect.");
    }

    // Listen for Shoelace drawer open/close events so we can hide the conversation panel
    // when the mobile chalkboard drawer is opened, and restore it when closed.
    this._drawerShowHandler = (e) => {
      try {
        const drawerId = e?.target?.dataset?.drawerId;
        if (drawerId === 'chalkboard') this.handleDrawerShow();
      } catch (err) { /* ignore */ }
    };

    this._drawerHideHandler = (e) => {
      try {
        const drawerId = e?.target?.dataset?.drawerId;
        if (drawerId === 'chalkboard') this.handleDrawerHide();
      } catch (err) { /* ignore */ }
    };

    document.addEventListener('sl-show', this._drawerShowHandler);
    document.addEventListener('sl-hide', this._drawerHideHandler);
  }

  disconnect() {
    // clean up listeners
    document.removeEventListener('sl-show', this._drawerShowHandler);
    document.removeEventListener('sl-hide', this._drawerHideHandler);
  }

  handleDrawerShow() {
    if (!this._originalParent) {
      this._originalParent = this.containerTarget.parentNode;
      this._originalClasses = this.containerTarget.className;
      //console.log("Original parent:", this._originalParent);
      //console.log("Original classes:", this._originalClasses);
    }

    // Move the entire chalkboard container into the drawer host if present
    if (!this.hostTarget.contains(this.containerTarget)) {
      this.hostTarget.appendChild(this.containerTarget);
      // Make sure it's visible and fills the drawer
      this.containerTarget.classList.remove('hidden', 'xl:flex', 'xl:flex-col', 'xl:grow');
      this.containerTarget.classList.add('flex', 'flex-col', 'h-full', 'w-full');
    }
  }

  handleDrawerHide() {
    // Move the chalkboard back to its original parent and restore classes
    //if (!this.container) {
    //  this.container = document.getElementById('chalkboard_container');
    //  if (!this.container) { console.warn("No chalkboard container to restore."); return; }
    //}

    if (this._originalParent) {
      //console.log("Restoring chalkboard to original parent:", this._originalParent);
      this._originalParent.appendChild(this.containerTarget);
      if (typeof this._originalClasses === 'string') {
        this.containerTarget.className = this._originalClasses;
      }
    } else {
      console.warn("Original parent not cached; nothing to restore.");
    }
  }

  printChalkboard() {
    document.body.classList.add("invisible")
    if (this.hasChalkboardTarget) {
      this.chalkboardTarget.classList.add("visible", "absolute", "top-0", "left-0", "h-full", "w-full")
      window.print()
      this.chalkboardTarget.classList.remove("visible", "absolute", "top-0", "left-0", "h-full", "w-full")
    } else {
      console.warn("No chalkboard target available for printing.");
    }
    document.body.classList.remove("invisible")
  }

  screenshotInstructions() {
    // Just show the user instructions on taking a screenshot.
    // This is better than using html-to-image which is hard to get to work, or Screen Capture API which is not meant for screenshots. 
    if (this.hasScreenshotDialogTarget) {
      this.screenshotDialogTarget.show();
    } else {
      console.warn("No screenshotDialog target found.");
    }
  }
/*
  // Image comes out blank, but keep here for future attempts.
  // Still, not as good as user learning to take their own screenshot, since they can crop with mouse to show what they want.
  async takeScreenshot() { // Take a screenshot of the chalkboard using html-to-image
    if (!this.hasChalkboardTarget) {
      console.warn("No chalkboard target for screenshot.");
      alert("Chalkboard not available for screenshots right now.");
      return;
    }

    const target = this.chalkboardTarget
    const rect = target.getBoundingClientRect()
    console.log("Chalkboard screenshot requested", {
      width: rect.width,
      height: rect.height,
      scrollWidth: target.scrollWidth,
      scrollHeight: target.scrollHeight,
      innerHTMLLength: target.innerHTML?.length
    })

    try {
      const computed = getComputedStyle(target)
      const backgroundColor = computed?.backgroundColor?.trim() || "#ffffff"

      const blob = await htmlToImage.toBlob(target, {
        cacheBust: true,
        backgroundColor,
        width: Math.max(target.scrollWidth, rect.width),
        height: Math.max(target.scrollHeight, rect.height),
        style: {
          padding: "16px",
          backgroundColor,
          color: computed?.color || "#111827",
          fontFamily: computed?.fontFamily
        },
        skipFonts: true
      })

      if (!blob) {
        throw new Error("html-to-image returned an empty blob")
      }

      window.dispatchEvent(new CustomEvent("chalkboard:screenshot", { detail: { blob } }))
      console.log("Chalkboard screenshot dispatched", blob)
    } catch (error) {
      console.error("Failed to capture chalkboard screenshot", error)
      alert("Couldn't capture the chalkboard automatically. We'll show manual instructions instead.")
      this.screenshotInstructions()
    }
  } */

  openWhiteboard() {
     //For now just open https://excalidraw.com/
     //Future goal to add a hosted whiteboard tool using importmap.
     if (this.hasChalkboardTarget) {
       this.chalkboardTarget.innerHTML = `<iframe src="https://excalidraw.com/" class="h-full w-full" allow="clipboard-read; clipboard-write;"></iframe>`
     } else {
       console.warn("No chalkboard target to open whiteboard in.");
     }
  }

}
