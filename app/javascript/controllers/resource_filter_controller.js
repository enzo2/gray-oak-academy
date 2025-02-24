import { Controller } from "@hotwired/stimulus"

// This controller is used to filter resources by name
export default class extends Controller {
  static targets = ["availableResource"]

  filterResources(event) {
    const searchTerm = event.target.value.toLowerCase()
    
    this.availableResourceTargets.forEach(resource => {
      const text = resource.textContent.toLowerCase()
      if (text.includes(searchTerm)) {
        resource.style.display = ""
      } else {
        resource.style.display = "none"
      }
    })
  }
}