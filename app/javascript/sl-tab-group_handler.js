// Handles Shoelace tab group close logic for all sl-tab-group elements

document.addEventListener("turbo:load", function() {
  document.querySelectorAll('sl-tab-group').forEach(tabGroup => {
    if (tabGroup.dataset.listenerAttached) return;
    tabGroup.dataset.listenerAttached = "true";
    tabGroup.addEventListener('sl-close', async event => {
      const tab = event.target;
      const panel = tabGroup.querySelector(`sl-tab-panel[name="${tab.panel}"]`);
      if (tab.active) {
        const prevTab = tab.previousElementSibling;
        if (prevTab && prevTab.panel) {
          tabGroup.show(prevTab.panel);
        }
      }
      tab.remove();
      panel?.remove();
    });
  });
});
