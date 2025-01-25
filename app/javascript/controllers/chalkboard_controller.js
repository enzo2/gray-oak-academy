import { Controller } from "@hotwired/stimulus"


export default class extends Controller {
  static targets = ["chalkboard", "printButton", "screenshotButton", "screenshotDialog"]
  
  connect() {
    //console.log("Chalkboard controller connected")
  }

  printChalkboard() {
    document.body.classList.add("invisible")
    this.chalkboardTarget.classList.add("visible", "absolute", "top-0", "left-0", "h-full", "w-full")
    window.print()
    this.chalkboardTarget.classList.remove("visible", "absolute", "top-0", "left-0", "h-full", "w-full")
    document.body.classList.remove("invisible")
  }

  sendScreenshot() {
    //Work in progress. 
    //Don't think available options aren't better than showing the user how to use their OS screen capture.
    //Screen Capture API requires https
    //html2canvas project is unmaintained and html2canvas-pro is possible malware
    //If this can be worked out then an LLM tool can also be added to retrieve a screenshot.
    this.screenshotDialogTarget.show();
  }

  openWhiteboard() {
     //For now just open https://excalidraw.com/
     this.chalkboardTarget.innerHTML = `<iframe src="https://excalidraw.com/" class="h-full w-full"></iframe>`
  }

}

