const THEME_MESSAGE_SOURCE = "goa-theme"
const THEME_REQUEST_SOURCE = "goa-theme-request"

export function currentAppletTheme() {
  return document.documentElement.classList.contains("dark") ? "dark" : "light"
}

export function appletFrameBackgroundColor(theme = currentAppletTheme()) {
  return theme === "dark" ? "#1c1917" : "#ffffff"
}

export function appletFrameBorderColor(theme = currentAppletTheme()) {
  return theme === "dark" ? "#57534e" : "#d6d3d1"
}

export function themedAppletUrl(url, theme = currentAppletTheme()) {
  if (!url) return url

  try {
    const parsed = new URL(url, window.location.origin)
    if (/^\/applets\/[^/]+\/run$/.test(parsed.pathname)) {
      parsed.searchParams.set("theme", theme)
    }
    return parsed.toString()
  } catch (_err) {
    return url
  }
}

export function postAppletTheme(targetWindow, theme = currentAppletTheme()) {
  targetWindow?.postMessage({ source: THEME_MESSAGE_SOURCE, v: 1, theme }, "*")
}

export function syncAppletIframeTheme(iframe, { border = false } = {}) {
  if (!iframe) return

  const theme = currentAppletTheme()
  iframe.style.backgroundColor = appletFrameBackgroundColor(theme)
  if (border) iframe.style.borderColor = appletFrameBorderColor(theme)
  postAppletTheme(iframe.contentWindow, theme)
}

export function attachAppletThemeRequestResponder(getIframes) {
  const handler = (event) => {
    const data = event.data || {}
    if (data.source !== THEME_REQUEST_SOURCE || data.v !== 1) return

    const iframe = Array.from(getIframes()).find((candidate) => candidate?.contentWindow === event.source)
    if (!iframe) return

    syncAppletIframeTheme(iframe, { border: iframe.dataset.appletThemeBorder === "true" })
  }

  window.addEventListener("message", handler)
  return () => window.removeEventListener("message", handler)
}
