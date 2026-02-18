import { Application } from "@hotwired/stimulus"

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

export { application }


// Dispatch events when Turbo cable stream sources connect or disconnect so listeners can react.
const streamConnectedEventName = "turbo:stream-connected";
const streamDisconnectedEventName = "turbo:stream-disconnected";
const turboCableStreamSourceName = "turbo-cable-stream-source";

const patchFlag = "__turboStreamLifecycleEventsPatched";
if (typeof window !== "undefined" && window.customElements?.whenDefined && !window[patchFlag]) {
  window[patchFlag] = true;
  // console.log("DEBUG: Installing Turbo stream lifecycle patch");

  window.customElements
    .whenDefined(turboCableStreamSourceName)
    .then(() => {
      const TurboCableStreamSource = window.customElements.get(turboCableStreamSourceName);
      if (!TurboCableStreamSource) return;

      const prototype = TurboCableStreamSource.prototype;

      const originalSubscriptionConnected = prototype.subscriptionConnected;
      prototype.subscriptionConnected = function (...args) {
        // console.log("DEBUG: Turbo Stream subscriptionConnected");
        const result = originalSubscriptionConnected?.apply(this, args);
        // console.log("DEBUG: Dispatching turbo:stream-connected");
        document.dispatchEvent(
          new CustomEvent(streamConnectedEventName, { detail: { source: this } })
        );
        return result;
      };

      const originalSubscriptionDisconnected = prototype.subscriptionDisconnected;
      prototype.subscriptionDisconnected = function (...args) {
        const result = originalSubscriptionDisconnected?.apply(this, args);
        document.dispatchEvent(
          new CustomEvent(streamDisconnectedEventName, { detail: { source: this } })
        );
        return result;
      };

      // If a stream source was already connected before the patch ran (e.g., on full page load),
      // emit the connected event so listeners can update their state.
      setTimeout(() => {
        const sources = document.querySelectorAll(turboCableStreamSourceName);
        // console.log(`DEBUG: Found ${sources.length} turbo-cable-stream-source elements for backfill`);
        sources.forEach((sourceElement) => {
          const flag = "__streamConnectedEventDispatched";
          const emitConnected = () => {
            if (sourceElement[flag]) return;
            if (!sourceElement.hasAttribute("connected")) return;
            sourceElement[flag] = true;
            // console.log("DEBUG: Backfilling turbo:stream-connected for existing or soon-connected source");
            document.dispatchEvent(
              new CustomEvent(streamConnectedEventName, { detail: { source: sourceElement } })
            );
          };

          // Try immediately
          emitConnected();

          // If not yet connected, watch for the connected attribute
          if (!sourceElement[flag]) {
            // console.log("DEBUG: Existing source not marked connected yet, observing for connected attribute");
            const observer = new MutationObserver(() => {
              emitConnected();
              if (sourceElement[flag]) observer.disconnect();
            });
            observer.observe(sourceElement, { attributes: true, attributeFilter: ["connected"] });
          }
        });
      }, 0);
    })
    .catch(() => {
      window[patchFlag] = false;
    });
}


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
