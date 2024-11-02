import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Find all pre elements with data-executable attribute
    const executableBlocks = this.element.querySelectorAll("pre[data-executable]")
    
    executableBlocks.forEach(block => {
      // Create execute button
      const button = document.createElement("button")
      button.textContent = "Run"
      button.className = "px-3 py-1 text-sm bg-green-500 text-white rounded hover:bg-green-600 ml-2"
      button.addEventListener("click", () => this.executeCode(block))
      
      // Create output div
      const output = document.createElement("div")
      output.className = "mt-2 p-2 bg-gray-100 text-black rounded"
      output.style.display = "none"
      
      // Insert elements
      block.parentNode.insertBefore(button, block.nextSibling)
      block.parentNode.insertBefore(output, button.nextSibling)
    })
  }
/*
  Instructions:
  When generating code responses, follow these guidelines:
  Format non-executable code or snippets using markdown as usual.
  You can create applets. Mark JavaScript as executable by wrapping it in a <pre data-executable> tag, without any <code> tag. 
  Use the sandbox object to append any created elements. For example:
    const slider = document.createElement('input');
    sandbox.appendChild(slider);
  Console is sandboxed. Use console.log() for any output that should be displayed as text to the user.
  Do not use document.body or any other global DOM methods. Instead, work within the provided sandbox environment.
  If you need to create event listeners, attach them to elements within the sandbox.
  The following APIs are available in the sandbox environment:
  - Basic DOM manipulation (createElement, createTextNode). (Don't use innerHTML.)
  - Fullscreen API
  - Promise API
  - Encoding API (TextEncoder, TextDecoder)
  - Audio APIs (AudioContext, OscillatorNode, GainNode, AnalyserNode, BiquadFilterNode, ConvolverNode, DelayNode, DynamicsCompressorNode, WaveShaperNode)
  - Canvas and WebGL (CanvasRenderingContext2D, WebGLRenderingContext)
  - IndexedDB API
  - Web Animations API (Animation, KeyframeEffect)
  - Intersection Observer API
  - Resize Observer API
  - Math and random functions
  - Typed arrays (Int8Array, Uint8Array, Int16Array, Uint16Array, Int32Array, Uint32Array, Float32Array, Float64Array)
  - Web Workers for parallel processing
*/
  executeCode(block) {
    // Check if there's a <code> tag inside the <pre> element
    if (block.querySelector("code")) {
      console.error("Execution cancelled: <code> tag found inside <pre data-executable>");
      return;
    }

    const code = block.textContent;

    const output = block.nextSibling.nextSibling;
    output.style.display = "block";
    output.textContent = ""; // Clear previous output
    output.classList.remove("text-red-500");

    try {
      // Create a sandbox div for DOM manipulation
      const sandbox = document.createElement('div');
      sandbox.className = 'sandbox';
      output.appendChild(sandbox);

      // Create a safe execution context
      const safeWindow = {
        console: {
          log: (...args) => {
            const text = args.map(arg =>
              typeof arg === "object" ? JSON.stringify(arg, null, 2) : String(arg)
            ).join(" ");
            const logElement = document.createElement('div');
            logElement.textContent = text;
            output.insertBefore(logElement, sandbox);
          },
          error: (...args) => {
            const text = args.map(arg => String(arg)).join(" ");
            const errorElement = document.createElement('div');
            errorElement.textContent = text;
            errorElement.classList.add("text-red-500");
            output.insertBefore(errorElement, sandbox);
          }
        },
        document: {
          createElement: (tagName) => document.createElement(tagName),
          createTextNode: (data) => document.createTextNode(data),
        },
        sandbox: sandbox,

        // Fullscreen API
        Fullscreen: window.Fullscreen,

        // Promise API
        Promise: window.Promise,

        // Encoding API
        TextEncoder: window.TextEncoder,
        TextDecoder: window.TextDecoder,

        // Audio APIs
        AudioContext: window.AudioContext,
        OscillatorNode: window.OscillatorNode,
        GainNode: window.GainNode,

        // Web Audio API additional nodes
        AnalyserNode: window.AnalyserNode,
        BiquadFilterNode: window.BiquadFilterNode,
        ConvolverNode: window.ConvolverNode,
        DelayNode: window.DelayNode,
        DynamicsCompressorNode: window.DynamicsCompressorNode,
        WaveShaperNode: window.WaveShaperNode,
        
        // Canvas and WebGL
        CanvasRenderingContext2D: window.CanvasRenderingContext2D,
        WebGLRenderingContext: window.WebGLRenderingContext,

        // IndexedDB API
        indexedDB: window.indexedDB,

        // Web Animations API
        Animation: window.Animation,
        KeyframeEffect: window.KeyframeEffect,

        // Intersection Observer API
        IntersectionObserver: window.IntersectionObserver,

        // Resize Observer API
        ResizeObserver: window.ResizeObserver,
        
        // Math and random functions
        Math: window.Math,
        Random: window.Math.random,
        
        // Typed arrays for efficient data handling
        Int8Array: window.Int8Array,
        Uint8Array: window.Uint8Array,
        Int16Array: window.Int16Array,
        Uint16Array: window.Uint16Array,
        Int32Array: window.Int32Array,
        Uint32Array: window.Uint32Array,
        Float32Array: window.Float32Array,
        Float64Array: window.Float64Array,

        // Web Workers for parallel processing
        Worker: window.Worker

      };

      // Execute the code with sandboxed environment
      const fn = new Function("window", `
        with (window) {
          ${code}
        }
      `);
      fn(safeWindow);
    } catch (error) {
      output.textContent = `Error: ${error.message}`;
      output.classList.add("text-red-500");
    }
  }
}