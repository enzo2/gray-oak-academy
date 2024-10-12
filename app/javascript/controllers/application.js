import { Application } from "@hotwired/stimulus"

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

export { application }

//clean up the toast notification if needed
document.addEventListener("turbo:before-stream-render", function() {
  document.body.querySelector("div.sl-toast-stack")?.remove();
});

//add turbo:after-stream-render event to trigger after render
//const afterRenderEvent = new Event("turbo:after-stream-render");
//addEventListener("turbo:before-stream-render", (event) => {
//  const originalRender = event.detail.render
//  event.detail.render = function (streamElement) {
//    originalRender(streamElement)
//    document.dispatchEvent(afterRenderEvent);
//  }
//})