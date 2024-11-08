import { Controller } from "@hotwired/stimulus"

// Tailwind classes used:
// print:hidden print:block print:bg-white print:w-full print:p-0

export default class extends Controller {
  static targets = ["chalkboard"]

  connect() {
    this.printButton = document.getElementById("printButton")
    this.printButton.addEventListener("click", this.prepareForPrint.bind(this))
  }

  disconnect() {
    this.printButton.removeEventListener("click", this.prepareForPrint)
  }

  prepareForPrint() {
    document.body.classList.add("print:hidden")
    this.chalkboardTarget.classList.add("print:block")
    window.print()
  }
}
