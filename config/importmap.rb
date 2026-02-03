# Pin npm packages by running ./bin/importmap
pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/channels", under: "channels"

# Custom JS
pin "turbo_stream_actions", to: "turbo_stream_actions.js"
pin "darkModeManager", to: "darkModeManager.js"
pin "sl-tab-group_handler", to: "sl-tab-group_handler.js"
pin "global_handlers", to: "global_handlers.js"

# Import shoelace components individually
pin "@shoelace-style/shoelace/cdn/utilities/base-path", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/utilities/base-path.js"
pin "@shoelace-style/shoelace/icon", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/icon/icon.js"
pin "@shoelace-style/shoelace/icon-button", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/icon-button/icon-button.js"
pin "@shoelace-style/shoelace/button", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/button/button.js"
pin "@shoelace-style/shoelace/spinner", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/spinner/spinner.js"
pin "@shoelace-style/shoelace/progress-bar", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/progress-bar/progress-bar.js"
pin "@shoelace-style/shoelace/tab-group", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/tab-group/tab-group.js"
pin "@shoelace-style/shoelace/tab-panel", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/tab-panel/tab-panel.js"
pin "@shoelace-style/shoelace/tab", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/tab/tab.js"
pin "@shoelace-style/shoelace/alert", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/alert/alert.js"
pin "@shoelace-style/shoelace/input", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/input/input.js"
pin "@shoelace-style/shoelace/dropdown", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/dropdown/dropdown.js"
pin "@shoelace-style/shoelace/menu-item", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/menu-item/menu-item.js"
pin "@shoelace-style/shoelace/menu", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/menu/menu.js"
pin "@shoelace-style/shoelace/dialog", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/dialog/dialog.js"
pin "@shoelace-style/shoelace/textarea", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/textarea/textarea.js"
pin "@shoelace-style/shoelace/details", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/details/details.js"
pin "@shoelace-style/shoelace/copy-button", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/copy-button/copy-button.js"
pin "@shoelace-style/shoelace/tree", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/tree/tree.js"
pin "@shoelace-style/shoelace/tree-item", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/tree-item/tree-item.js"
pin "@shoelace-style/shoelace/drawer", to: "https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/components/drawer/drawer.js"

# Webawesome (Shoelace Successor)
# pin "@awesome.me/webawesome/dist-cdn/webawesome", to: "https://cdn.jsdelivr.net/npm/@awesome.me/webawesome@3.0.0/dist-cdn/webawesome.js"
# pin "@awesome.me/webawesome/button", to: "https://cdn.jsdelivr.net/npm/@awesome.me/webawesome@3.0.0/dist-cdn/components/button/button.js"
# pin "@awesome.me/webawesome/icon", to: "https://cdn.jsdelivr.net/npm/@awesome.me/webawesome@3.0.0/dist-cdn/components/icon/icon.js"

pin "katex", to: "https://cdn.jsdelivr.net/npm/katex@0.16.25/dist/katex.js"
pin "katex-auto-render", to: "https://cdn.jsdelivr.net/npm/katex@0.16.25/dist/contrib/auto-render.min.js"

pin "@floating-ui/dom", to: "https://cdn.jsdelivr.net/npm/@floating-ui/dom@1.7.4/+esm"

# pin "html-to-image", to: "https://cdn.jsdelivr.net/npm/html-to-image/+esm"

# Try adding Excalidraw to the chalkboard? Requires React....
# pin "@excalidraw/excalidraw", to: "https://cdn.jsdelivr.net/npm/@excalidraw/excalidraw@0.17.6/dist/excalidraw.production.min.js"
