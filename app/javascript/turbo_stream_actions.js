import { Turbo } from "@hotwired/turbo-rails"

// Define the 'dispatch_event' custom action
Turbo.StreamActions.dispatch_event = function() {
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
  targetElement.dispatchEvent(event);
};