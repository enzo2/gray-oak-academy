import { Controller } from "@hotwired/stimulus"

// This controller is used to filter resources by name
export default class extends Controller {
  static targets = ["availableResource", "emptyState", "searchInput", "tagSelect", "categorySelect"]

  filterResources(event) {
    const searchTerm = (this.hasSearchInputTarget ? this.searchInputTarget.value : event.target.value).toLowerCase().trim()
    const selectedTag = this.hasTagSelectTarget ? this.tagSelectTarget.value.toLowerCase().trim() : ""
    const selectedCategory = this.hasCategorySelectTarget ? this.categorySelectTarget.value.toLowerCase().trim() : ""
    let visibleCount = 0
    
    this.availableResourceTargets.forEach(resource => {
      const text = (resource.dataset.resourceFilterSearchable || resource.textContent).toLowerCase()
      const tagList = (resource.dataset.resourceFilterTags || "").toLowerCase().split(",").map(tag => tag.trim()).filter(Boolean)
      const category = (resource.dataset.resourceFilterCategory || "").toLowerCase().trim()
      const matchesSearch = text.includes(searchTerm)
      const matchesTag = !selectedTag || tagList.includes(selectedTag)
      const matchesCategory = !selectedCategory || category === selectedCategory
      const matches = matchesSearch && matchesTag && matchesCategory
      resource.classList.toggle("hidden", !matches)
      if (matches) visibleCount += 1
    })

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.toggle("hidden", visibleCount > 0)
    }
  }
}
