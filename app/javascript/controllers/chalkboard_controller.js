import { Controller } from "@hotwired/stimulus"

// For future use, if can get it to work
//import * as htmlToImage from 'html-to-image';
//import { toJpeg, toBlob } from 'html-to-image';

export default class extends Controller {
  static targets = ["chalkboard", "screenshotDialog", "screenSizeWarning"]
  
  connect() {
    //console.log("Chalkboard controller connected")
    
    //Display the warning dialog if the user's screen is below tailwind 'xl' breakpoint.
    // Disabled for now as it could be annoying. 
    if (window.innerWidth < 1280) {
      //document.body.appendChild(this.screenSizeWarningTarget).show();
    }
  }

  printChalkboard() {
    document.body.classList.add("invisible")
    this.chalkboardTarget.classList.add("visible", "absolute", "top-0", "left-0", "h-full", "w-full")
    window.print()
    this.chalkboardTarget.classList.remove("visible", "absolute", "top-0", "left-0", "h-full", "w-full")
    document.body.classList.remove("invisible")
  }

  screenshotInstructions() {
    //Available options aren't better than showing the user how to use their OS native screen capture.
    //If this can be worked out, then an LLM tool can also be added to retrieve a screenshot.
    //For now, just show the user instructions on taking a screenshot.
    this.screenshotDialogTarget.show();
  }

  // Image comes out blank, but keep here for future attempts:
  // Take a screenshot of the chalkboard using html-to-image
  takeScreenshot() {
    htmlToImage.toBlob(this.chalkboardTarget).then((blob) => {
      if (!blob) { alert("Failed to capture screenshot."); return; }
      // Event dispatched with the screenshot blob
      // This can be handled by the new-message-controller to add the image to the message input
      this.dispatch("screenshot", { detail: { blob } });
      console.log("Screenshot taken and dispatched", blob);
    });
  }

  openWhiteboard() {
     //For now just open https://excalidraw.com/
     //Future goal to add a hosted whiteboard tool using importmap.
     this.chalkboardTarget.innerHTML = `<iframe src="https://excalidraw.com/" class="h-full w-full" allow="clipboard-read; clipboard-write;"></iframe>`
  }

}
