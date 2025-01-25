import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chalkboard", "printButton"]
  
  print() {

    // This is a work in progress.
    
    document.body.classList.add("invisible")
    this.chalkboardTarget.classList.add("visible", "absolute", "top-0", "left-0", "h-full", "w-full")
    window.print()
    this.chalkboardTarget.classList.remove("visible", "absolute", "top-0", "left-0", "h-full", "w-full")
    document.body.classList.remove("invisible")

  }
}
