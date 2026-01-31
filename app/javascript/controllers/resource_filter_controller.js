import { Controller } from "@hotwired/stimulus"

// This controller is used to filter resources by name
export default class extends Controller {
  static targets = ["availableResource", "emptyState"]

  filterResources(event) {
    const searchTerm = event.target.value.toLowerCase().trim()
    let visibleCount = 0
    
    this.availableResourceTargets.forEach(resource => {
      const text = (resource.dataset.resourceFilterSearchable || resource.textContent).toLowerCase()
      const matches = text.includes(searchTerm)
      resource.classList.toggle("hidden", !matches)
      if (matches) visibleCount += 1
    })

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.toggle("hidden", visibleCount > 0)
    }
  }
}
