import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["entries", "pagination"]
  static values = {
    url: String,
    page: { type: Number, default: 1 }
  }

  connect() {
    this.createObserver()
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  createObserver() {
    if (!this.hasPaginationTarget) return

    this.observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          this.load()
        }
      })
    }, { rootMargin: "200px" }) // Load 200px before end

    this.observer.observe(this.paginationTarget)
  }

  async load() {
    if (this.isLoading || !this.hasUrlValue) return

    this.isLoading = true
    const url = new URL(this.urlValue, window.location.href)
    url.searchParams.set("page", this.pageValue)

    try {
      console.log(`Loading page ${this.pageValue} from ${url.toString()}`)
      
      const tokenMeta = document.querySelector('meta[name="csrf-token"]')
      const token = tokenMeta ? tokenMeta.content : ""
      
      const headers = {
        "Accept": "text/vnd.turbo-stream.html"
      }
      if (token) {
        headers["X-CSRF-Token"] = token
      }

      const response = await fetch(url.toString(), {
        headers: headers
      })

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
        this.pageValue++
        console.log(`Loaded page ${this.pageValue - 1}`)
      } else {
        // If 204 No Content or similar (end of list), disable url?
        this.urlValue = "" 
      }
    } catch (error) {
      console.error("Failed to load journal entries:", error)
    } finally {
      this.isLoading = false
    }
  }
}
