import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "source", "successDialog" ]

  connect () {
    //console.log("connected")
  }

  async copy(event) { 
    const button = event.currentTarget; 
    const url = button.dataset.copyCodeUrl;

    try {
      const response = await fetch( url, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
        }
      });
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      const data = await response.json();
      const code = data.code;
    
      await navigator.clipboard.writeText(code);
      this.successDialogTarget.show();
      console.log("Code copied to clipboard!");
    
    } catch (error) {
      console.error("Could not fetch or copy code:", error);
      // Consider showing an error message to the user.
      alert("Failed to copy code.");
    }
  } 
}
