import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["entries", "pagination"]
  static values = {
    url: String,
    page: { type: Number, default: 1 }
  }

  connect() {
    // Only load when the element becomes visible
    const observer = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          this.load()
          observer.disconnect()
        }
      })
    })
    observer.observe(this.element)
  }

  scroll() {
    const { scrollTop, clientHeight, scrollHeight } = document.documentElement
    // Fallback for older browsers or specific modes if documentElement doesn't work
    const docHeight = Math.max(
      document.body.scrollHeight, document.documentElement.scrollHeight,
      document.body.offsetHeight, document.documentElement.offsetHeight,
      document.body.clientHeight, document.documentElement.clientHeight
    )
    const winHeight = window.innerHeight || document.documentElement.clientHeight
    const winScroll = window.scrollY || window.pageYOffset || document.body.scrollTop + (document.documentElement && document.documentElement.scrollTop || 0)

    if (winScroll + winHeight >= docHeight - 100) {
      this.load()
    }
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
