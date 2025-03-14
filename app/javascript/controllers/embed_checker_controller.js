import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "dialog", "embedCheckerIframe"]

  connect() {
    //console.log("Embed checker controller connected")
  }

  openDialog() {
    //console.log("Open dialog")
    this.dialogTarget.show()
    this.checkEmbed()
  }

  checkEmbed() {
    //console.log("Check embed")
    const url = document.getElementById("resource_uri").value
    this.embedCheckerIframeTarget.src = url
  }
}
