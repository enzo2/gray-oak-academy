import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Find all pre elements with data-executable attribute
    this.setupExecutableBlocks();
  }

  setupExecutableBlocks() {
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
  Inline applets will be executed within an iframe with about 400px of height and 550px width within the conversation.
  By default there is a light background with dark text.
  This sandbox contains a <div id="sandbox">, available as the sandbox object.
  Use the sandbox object to append any created elements. For example:
    const slider = document.createElement('input');
    sandbox.appendChild(slider);
  Console is also sandboxed. Use console.log() for any output that should be displayed as text to the user.
  You can use APIs like Fullscreen, Promise, Audio, Canvas, WebGL, Web Animations, etc.
  Do not access the microphone or camera.   
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

    // Create a sandboxed iframe
    const iframe = document.createElement('iframe');
    iframe.sandbox = 'allow-scripts allow-modals allow-pointer-lock allow-popups allow-presentation';
    iframe.allow = 'fullscreen';
    iframe.style.width = '100%';
    iframe.style.height = '400px';
    iframe.style.border = '1px solid #ccc';
    output.appendChild(iframe);

    // Prepare the content for the iframe
    const iframeContent = `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: Arial, sans-serif; padding: 10px; }
          .error { color: red; }
        </style>
      </head>
      <body>
        <div id="sandbox"></div>
        <script>
          const sandbox = document.getElementById('sandbox');
          const console = {
            log: (...args) => {
              const logElement = document.createElement('div');
              logElement.textContent = args.join(' ');
              sandbox.appendChild(logElement);
            },
            error: (...args) => {
              const errorElement = document.createElement('div');
              errorElement.textContent = args.join(' ');
              errorElement.className = 'error';
              sandbox.appendChild(errorElement);
            }
          };

          try {
            ${code}
          } catch (error) {
            console.error('Error:', error.message);
          }
        </script>
      </body>
      </html>
    `;

    // Set the content of the iframe
    iframe.srcdoc = iframeContent;
  }
}
