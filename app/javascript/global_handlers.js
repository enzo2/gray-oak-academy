// Global event handlers to replace inline 'onclick' attributes
document.addEventListener('click', (event) => {
  // Handle Menu Item Clicks (find child button/link and click it)
  // Replaces: <sl-menu-item onclick="this.children[0].click">
  const clickChild = event.target.closest('[data-click-child]');
  if (clickChild) {
    const child = clickChild.querySelector('a, button');
    // Prevent infinite loop if the child is what was clicked
    if (child && event.target !== child && !child.contains(event.target)) {
        child.click();
    }
  }

  // Handle Dialog Show
  // Replaces: onclick="document.getElementById('id').show()"
  const showTrigger = event.target.closest('[data-show-dialog]');
  if (showTrigger) {
    const dialogId = showTrigger.dataset.showDialog;
    const dialog = document.getElementById(dialogId);
    if (dialog) dialog.show();
  }

  // Handle Dialog Hide
  // Replaces: onclick="this.closest('sl-dialog').hide()"
  const hideTrigger = event.target.closest('[data-hide-dialog]');
  if (hideTrigger) {
     const dialog = hideTrigger.closest('sl-dialog');
     if (dialog) dialog.hide();
  }

  // Handle Dispatch Event
  // Replaces: onclick="window.dispatchEvent(new CustomEvent('...'))"
  const dispatchTrigger = event.target.closest('[data-dispatch-event]');
  if (dispatchTrigger) {
      const eventName = dispatchTrigger.dataset.dispatchEvent;
      window.dispatchEvent(new CustomEvent(eventName));
  }
});
