import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export default class extends Controller {
  static targets = ["entries", "pagination"]
  static values = {
    url: String,
    page: { type: Number, default: 1 }
  }

  connect() {
    //console.log("InfiniteScrollController connected")
    this.load()
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
      const response = await get(url.toString(), { responseKind: "turbo-stream" })
      if (response.ok) {
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
