import { Controller } from "@hotwired/stimulus"

/* Usage: 
<div data-controller="modal">
  <button data-action="modal#open">Open</button>
  <div data-modal-target="content" class="hidden">
    <!-- Your Content -->
    <button data-action="modal#close">Close</button>
  </div>
</div>
*/

export default class extends Controller {
  static targets = ["content"]
  static values = {
    panelClass: { 
      type: String, 
      default: "relative transform overflow-hidden rounded-lg bg-white dark:bg-stone-900 text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg border border-stone-200 dark:border-stone-700" 
    }
  }

  connect() {
    // Pre-bind the handleKeydown method so we can add/remove it easily
    this.boundHandleKeydown = this.handleKeydown.bind(this)
    this.boundClose = this.close.bind(this)
  }

  disconnect() {
    // Clean up if the controller is disconnected while modal is open
    if (this.modalWrapper) {
      this.close()
    }
  }

  open(event) {
    if (event) event.preventDefault()
    
    // specific to this implementation:
    // We need to capture the element before moving it, because once it leaves the 
    // controller's scope, this.contentTarget will throw an error.
    this.contentElement = this.contentTarget

    // Create the modal structure
    this.buildModalStructure()
    
    // Move the content into the panel
    this.panel.appendChild(this.contentElement)
    
    // Reveal the content (it was hidden in the view)
    this.contentElement.classList.remove("hidden")
    
    // Bind events to any elements with data-action="modal#close" inside the modal
    // We have to do this manually because the element is now outside the controller's scope
    this.closeButtons = this.contentElement.querySelectorAll('[data-action~="modal#close"]')
    this.closeButtons.forEach(button => {
      button.addEventListener("click", this.boundClose)
    })

    // Add to body
    document.body.appendChild(this.modalWrapper)
    document.body.classList.add("overflow-hidden")
    
    // Add event listener for Escape
    window.addEventListener("keydown", this.boundHandleKeydown)
  }

  close(event) {
    if (event && event.preventDefault) event.preventDefault()
    
    if (this.modalWrapper) {
      // Remove manual event listeners
      if (this.closeButtons) {
        this.closeButtons.forEach(button => {
          button.removeEventListener("click", this.boundClose)
        })
        this.closeButtons = null
      }

      // Hide content again
      if (this.contentElement) {
        this.contentElement.classList.add("hidden")
        
        // Move content back to its original place
        this.element.appendChild(this.contentElement)
      }
      
      // Remove the modal structure from DOM
      this.modalWrapper.remove()
      this.modalWrapper = null
      this.contentElement = null
      
      document.body.classList.remove("overflow-hidden")
      window.removeEventListener("keydown", this.boundHandleKeydown)
    }
  }

  closeBackground(event) {
    if (event.target === this.backdropContainer) {
      this.close(event)
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close(event)
    }
  }

  buildModalStructure() {
    // 1. Outer wrapper (z-index, full screen)
    this.modalWrapper = document.createElement("div")
    this.modalWrapper.className = "relative z-50"
    this.modalWrapper.setAttribute("aria-labelledby", "modal-title")
    this.modalWrapper.setAttribute("role", "dialog")
    this.modalWrapper.setAttribute("aria-modal", "true")

    // 2. Backdrop (dark overlay)
    const backdrop = document.createElement("div")
    backdrop.className = "fixed inset-0 bg-gray-500/75 transition-opacity"
    this.modalWrapper.appendChild(backdrop)

    // 3. Scrollable container
    this.backdropContainer = document.createElement("div")
    this.backdropContainer.className = "fixed inset-0 z-10 w-full overflow-y-auto"
    
    // Click backdrop to close
    this.backdropContainer.addEventListener("click", (e) => this.closeBackground(e))

    this.modalWrapper.appendChild(this.backdropContainer)

    // 4. Centering flex container
    const flexContainer = document.createElement("div")
    flexContainer.className = "flex min-h-full items-center justify-center p-4"
    // Ensure clicks on the Flex container (which shouldn't happen due to full width children, but safety first) bubble to backdropContainer
    flexContainer.style.pointerEvents = "none" 

    this.backdropContainer.appendChild(flexContainer)

    // 5. The generic Panel (White box)
    this.panel = document.createElement("div")
    this.panel.className = this.panelClassValue
    // Re-enable pointer events for the panel
    this.panel.style.pointerEvents = "auto"

    flexContainer.appendChild(this.panel)
  }
}
