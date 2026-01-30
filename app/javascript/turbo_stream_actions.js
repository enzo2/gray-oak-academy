// Custom turbo_stream actions to extend functionality for Turbo::StreamsChannel.broadcast_action_to().

import { Turbo } from "@hotwired/turbo-rails"

// Adds dispatch_event as a custom Turbo Stream action.
// This allows custom events to be dispatched from the server via turbo stream,
// over the existing websocket connection (turbo_stream_from helper)
// A target-selector can be specified to limit the scope of the event, otherwise 
// the event will be dispatched to the document.
// Define the 'dispatch_event' custom action
const dispatchEventAction = function() {
  const eventName = this.getAttribute("event-name")
  const targetSelector = this.getAttribute("target-selector") // Optional: CSS selector for target element
  const detail = JSON.parse(this.templateContent?.textContent || "{}") // Optional: Event detail payload

  if (!eventName) {
    console.error("Turbo Stream 'dispatch_event' action requires an 'event-name' attribute.")
    return
  }

  const event = new CustomEvent(eventName, { detail: detail, bubbles: true })

  // Determine the target element for dispatching the event
  let targetElement = document; // Default to document
  if (targetSelector) {
    targetElement = document.querySelector(targetSelector);
    if (!targetElement) {
      console.warn(`Turbo Stream 'dispatch_event': Target element not found for selector "${targetSelector}". Dispatching on document.`);
      targetElement = document;
    }
  }

  // Dispatch the event
  //console.log(`Dispatching event '${eventName}' on ${targetElement === document ? 'document' : targetSelector}`, detail);
  targetElement.dispatchEvent(event)
}

// Define the 'visit' custom action for navigating to a URL via Turbo
const visitAction = function() {
  const url = this.getAttribute("url")
  const action = this.getAttribute("visit-action") || "advance"

  if (!url) {
    console.error("Turbo Stream 'visit' action requires a 'url' attribute.")
    return
  }

  Turbo.visit(url, { action: action })
}

Turbo.StreamActions.dispatch_event = dispatchEventAction
Turbo.StreamActions.visit = visitAction
