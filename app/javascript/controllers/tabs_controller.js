import { Controller } from "@hotwired/stimulus"

// Generic tab controller — mirrors the navbar_controller data-content-id
// pattern so triggers and panels are linked by id.
//
// Usage:
//
//   <div data-controller="tabs" data-tabs-active-tab-value="panel-a">
//
//     <div role="tablist">
//       <button role="tab" type="button"
//               class="rounded border border-transparent px-2 py-1"
//               data-tabs-target="tab"
//               data-tabs-panel="panel-a"
//               data-action="click->tabs#show keydown->tabs#handleTabKeydown">
//         Panel A
//       </button>
//
//       <!-- Tab that is "active" when any of its group panels is shown: -->
//       <button role="tab" type="button"
//               data-tabs-target="tab"
//               data-tabs-panel="panel-b"
//               data-tabs-group="panel-b panel-c panel-d"
//               data-action="click->tabs#show keydown->tabs#handleTabKeydown">
//         Group Tab
//       </button>
//     </div>
//
//     <div id="panel-a" role="tabpanel" data-tabs-target="panel">...</div>
//     <div id="panel-b" role="tabpanel" data-tabs-target="panel">...</div>
//     ...
//
//   </div>
//
// data-tabs-panel     — id of the panel this tab activates when clicked.
// data-tabs-group     — space-separated list of panel ids; the tab shows as active when
//                       any panel in the group is currently shown (used for dropdown groups).
// data-tabs-active-tab-value — id of the initially active panel (falls back to first tab's panel).
//
// Note: uses data-tabs-panel (not data-content-id) so it can coexist with the
// navbar controller on the same element without attribute conflicts.
//
// CSS hooks:
//   [data-state="open"]   — active tab button
//   [data-state="closed"] — inactive tab buttons

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { activeTab: String }

  connect() {
    this.currentTabId = null
    this.boundRefresh = () => {
      requestAnimationFrame(() => {
        if (this.element.isConnected) this.refresh()
      })
    }

    document.addEventListener("turbo:render", this.boundRefresh)
    this.refresh({ initial: true })
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.boundRefresh)
  }

  // Action: click->tabs#show
  show(event) {
    const trigger = event.currentTarget
    const contentId = trigger.dataset.tabsPanel
    // For dropdown trigger tabs, keep the current sub-tab when already inside
    // that tab group so opening the menu doesn't jump back to the default tab.
    if (trigger.dataset.tabsMenuTrigger === "true" && this.isCurrentTabInGroup(trigger)) return

    if (contentId) this.showTab(contentId)
  }

  // Action: keydown->tabs#handleTabKeydown
  // Implements the WAI-ARIA tabs keyboard pattern.
  handleTabKeydown(event) {
    const tabs = this.tabTargets
    const index = tabs.indexOf(event.currentTarget)
    const isMenuTrigger = event.currentTarget.dataset.tabsMenuTrigger === "true"
    let next = null

    switch (event.key) {
      case "ArrowLeft":
        next = tabs[index > 0 ? index - 1 : tabs.length - 1]
        break
      case "ArrowRight":
        next = tabs[index < tabs.length - 1 ? index + 1 : 0]
        break
      case "ArrowUp":
      case "ArrowDown":
        // Allow dropdown-enabled tabs to delegate vertical arrows to menu logic.
        if (isMenuTrigger) return
        if (event.key === "ArrowUp") {
          next = tabs[index > 0 ? index - 1 : tabs.length - 1]
        } else {
          next = tabs[index < tabs.length - 1 ? index + 1 : 0]
        }
        break
      case "Home":
        next = tabs[0]
        break
      case "End":
        next = tabs[tabs.length - 1]
        break
      default:
        return
    }

    event.preventDefault()
    next.focus()
    this.showTab(next.dataset.tabsPanel)
  }

  showTab(contentId, { initial = false } = {}) {
    const resolvedContentId = this.resolvePanelId(contentId)
    if (!resolvedContentId) return

    this.currentTabId = resolvedContentId

    this.tabTargets.forEach(tab => {
      const panelId = tab.dataset.tabsPanel
      const group = tab.dataset.tabsGroup ? tab.dataset.tabsGroup.split(" ") : []
      const active = panelId === resolvedContentId || group.includes(resolvedContentId)
      tab.dataset.state = active ? "open" : "closed"
      tab.setAttribute("aria-selected", active.toString())
      tab.setAttribute("tabindex", active ? "0" : "-1")
    })

    this.panelTargets.forEach(panel => {
      const active = panel.id === resolvedContentId
      panel.classList.toggle("hidden", !active)
      panel.setAttribute("aria-hidden", (!active).toString())
    })

    this.dispatch("change", { detail: { tab: resolvedContentId, initial } })
  }

  refresh({ initial = false } = {}) {
    const fallback = this.tabTargets[0]?.dataset.tabsPanel
    const preferred = this.currentTabId || this.activeTabValue || fallback
    const resolvedTabId = this.resolvePanelId(preferred, fallback)
    if (resolvedTabId) this.showTab(resolvedTabId, { initial })
  }

  resolvePanelId(contentId, fallbackId = this.tabTargets[0]?.dataset.tabsPanel) {
    const exists = (id) => id && this.panelTargets.some(panel => panel.id === id)
    if (exists(contentId)) return contentId
    if (exists(fallbackId)) return fallbackId
    return this.panelTargets[0]?.id
  }

  isCurrentTabInGroup(trigger) {
    const group = trigger.dataset.tabsGroup ? trigger.dataset.tabsGroup.split(" ") : []
    return !!this.currentTabId && (trigger.dataset.tabsPanel === this.currentTabId || group.includes(this.currentTabId))
  }
}
