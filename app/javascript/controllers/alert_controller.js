import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="alert" to show flash shoelace alerts as toast
export default class extends Controller {
  static targets = [ "alert" ]

  alertTargetConnected(alert){
    alert.toast();
  }

  alertTargetDisconnected(alert){
    alert.hide();
  }

}