import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form"]
  static outlets = ["infinite-scroll"]

  initialize() {
    this.observer = new MutationObserver(() => {
      this.filter()
    })
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  infiniteScrollOutletConnected(outlet, element) {
    if (outlet.hasEntriesTarget) {
      this.observer.observe(outlet.entriesTarget, { childList: true })
    }
    this.filter()
  }

  infiniteScrollOutletDisconnected(outlet, element) {
    // We don't strictly need to disconnect the observer here because 
    // if the outlet element is removed, intersection observer on it stops mattering,
    // but good practice to stop observing a node if we lose track of it.
    // However, MutationObserver.disconnect stops observing ALL nodes.
    // Since we only observe one outlet's target, this is fine.
    this.observer.disconnect()
  }

  filter() {
    console.log("filter");
    if (!this.hasFormTarget || !this.hasInfiniteScrollOutlet) return

    const formData = new FormData(this.formTarget)
    
    let activeTypes = formData.getAll("types")
    if (activeTypes.length === 0) {
        activeTypes = formData.getAll("types[]")
    }

    // Console log for debugging
    console.log("Filtering:", { activeTypes })

    const container = this.infiniteScrollOutlet.entriesTarget
    const items = container.querySelectorAll(".journal-entry")
    
    items.forEach(item => {
       const type = item.dataset.journalType
       
       let visible = true
       
       // Logic: If unchecked, hide it.
       // If activeTypes is empty, it means nothing is checked (or nothing submitted).
       // UI has checkboxes. If uncheck all, activeTypes is empty array.
       // If activeTypes is empty, we should hide everything that has a type.
       
       if (!activeTypes.includes(type)) {
           visible = false
       }
       
       if (visible) {
           item.classList.remove("hidden")
       } else {
           item.classList.add("hidden")
       }
    })
  }
}
