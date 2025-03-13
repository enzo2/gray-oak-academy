import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="alert" to show flash shoelace alerts as toast
export default class extends Controller {
  static targets = [ "alert" ]

  alertTargetConnected(alert){
    alert.toast();
    //console.log("showing toast")
  }

  alertTargetDisconnected(alert){
    //User has to manually close the toast
    //alert.hide();
    //console.log("hiding toast")
  }

}