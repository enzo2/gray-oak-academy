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


//https://discuss.hotwired.dev/t/event-to-know-a-turbo-stream-has-been-rendered/1554/25
//add turbo:after-stream-render event
//see https://github.com/hotwired/turbo/issues/1289
const afterRenderEvent = new Event("turbo:after-stream-render");
addEventListener("turbo:before-stream-render", (event) => {
  const originalRender = event.detail.render
  event.detail.render = function (streamElement) {
    originalRender(streamElement)
    document.dispatchEvent(afterRenderEvent);
    //console.log("turbo:after-stream-render event dispatched")
  }
});
