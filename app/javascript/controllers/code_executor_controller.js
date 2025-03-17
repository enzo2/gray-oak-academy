import { Controller } from "@hotwired/stimulus"

/*
  This controller is responsible for setting up executable javascript applets in the conversation.

  LLM instructions - found in seeds.rb.
*/

export default class extends Controller {
  static targets = ["chalkboard", "message"]

  connect() {
    //console.log("code-executor-controller connected");
  }

  // Called when a new message is added to the conversation.
  messageTargetConnected(messageElement) {
    this.setupExecutableBlocks(messageElement);
    //console.log("messageTargetConnected");
  }

  setupExecutableBlocks(element) {
    // Find all executable code blocks in the message.
    const executableBlocks = element.querySelectorAll("pre[data-executable]");

    executableBlocks.forEach(block => {
      // Ensure the block ends with the expected closing tag.
      const endOfBlock = block.outerHTML.slice(-30).trim();
      if (!endOfBlock.match(/\/\/EOB\s*<\/pre>$/)) return;

      console.log("Discovered executable code block.");

      // Extract the configuration from the block's data attributes.
      const config = {
        hidden: block.dataset.hidden !== 'false', // Default to hidden unless explicitly set to false
        autoRun: block.dataset.autoRun === 'true',
        renderTarget: block.dataset.renderTarget || 'chalkboard'
      };

      this.setupBlock(block, config);
    });
  }

  // Main function for setting up the code block.
  setupBlock(block, config) {

    // Create a container div to hold the block and its associated buttons.
    const container = this.createContainer(block);

    // Hide the block by default unless explicitly shown
    if (config.hidden) {
      this.setupHiddenBlock(block, container);
    }

    const button = this.createRunButton(block, config.renderTarget);
    container.appendChild(button);

    const archiveButton = this.createArchiveButton(block);
    container.appendChild(archiveButton);

    // Create an output div if the render target is inline.
    if (config.renderTarget === 'inline') {
      const output = this.createOutputDiv();
      container.appendChild(output);
    }

    if (config.autoRun) {
      this.executeCode(block, config.renderTarget);
    }

    console.log("Applet has been set up!");
  }

  // Creates a container div to hold the block and its associated buttons.
  createContainer(block) {
    const container = document.createElement("div");
    container.className = "relative";
    block.parentNode.insertBefore(container, block);
    container.appendChild(block);
    return container;
  }

  // Sets up the block to be hidden initially and adds a toggle button.
  setupHiddenBlock(block, container) {
    block.style.display = 'none';
    const toggleBtn = this.createToggleButton(block);
    container.insertBefore(toggleBtn, block);
  }

  createToggleButton(block) {
    const toggleBtn = document.createElement("button");
    toggleBtn.textContent = "Show Code";
    toggleBtn.className = "px-3 py-1 text-sm bg-blue-500 text-white rounded-sm hover:bg-blue-600 font-sans";
    toggleBtn.addEventListener("click", () => {
      const isHidden = block.style.display === 'none';
      block.style.display = isHidden ? 'block' : 'none';
      toggleBtn.textContent = isHidden ? "Hide Code" : "Show Code";
    });
    return toggleBtn;
  }

  createRunButton(block, renderTarget) {
    const button = document.createElement("button");
    button.textContent = "Run";
    button.className = "px-3 py-1 text-sm font-sans bg-green-500 text-white rounded-sm hover:bg-green-600 ml-2";
    button.addEventListener("click", () => this.executeCode(block, renderTarget));
    return button;
  }

  createArchiveButton(block) {
    const button = document.createElement("button");
    button.textContent = "Archive";
    button.className = "px-3 py-1 text-sm font-sans bg-stone-500 text-white rounded-sm hover:bg-stone-600 ml-2";
    button.addEventListener("click", () => this.archiveApplet(block));
    return button;
  }

  createOutputDiv() {
    const output = document.createElement("div");
    output.className = "mt-2 p-2 bg-stone-100 text-black rounded-sm";
    output.style.display = "none";
    return output;
  }

  executeCode(block, renderTarget = 'inline') {
    if (block.querySelector("code")) {
      console.error("Execution cancelled: <code> tag found inside <pre data-executable>");
      return;
    }

    // Get the code from the block
    const code = block.textContent;
    const output = this.getOutputElement(block, renderTarget);
    if (!output) return;

    output.innerHTML = ''; // Clear previous content
    const iframe = this.createSandboxedIframe(renderTarget);
    output.appendChild(iframe);

    const iframeContent = this.prepareIframeContent(code);
    iframe.srcdoc = iframeContent;
  }

  // Helper method to get the output element based on the render target
  getOutputElement(block, renderTarget) {
    if (renderTarget === 'chalkboard') { //Use the chalkboard as output
      const output = this.chalkboardTarget;
      if (!output) {
        console.error("Chalkboard element not found");
        return null;
      }
      output.style.display = "block";
      output.innerHTML = "";
      return output;
    } else  { //Use the inline output div as output
      const output = block.parentNode.querySelector("div:last-child");
      if (!output) {
        console.error("Inline output element not found");
        return null;
      }
      output.style.display = "block";
      output.textContent = "";
      output.classList.remove("text-red-500");
      return output;
    }
  }

  createSandboxedIframe(renderTarget) {
    const iframe = document.createElement('iframe');
    iframe.sandbox = 'allow-scripts allow-modals allow-pointer-lock allow-popups allow-presentation';
    iframe.allow = 'fullscreen';
    iframe.style.width = '100%';
    iframe.style.height = renderTarget === 'chalkboard' ? '100%' : '400px';
    iframe.style.border = '1px solid #ccc';
    return iframe;
  }

  prepareIframeContent(code) {
    return `
      <!DOCTYPE html>
      <html>
      <head>
        <style>
          body { font-family: "Segoe UI", Optima, Futura, "Gill Sans MT", "Gill Sans", sans-serif; padding: 10px; }
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
  }

  archiveApplet(block) {
    const code = block.textContent.replace(/<pre.*?>(.*?)<\/pre>/s, '$1').trim();
    const title = prompt("Enter a name for this applet:");
    if (!title) return;

    fetch('/applets', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
      },
      body: JSON.stringify({ applet: { title: title, code: code, archived: true } })
    })
    .then(response => {
      if (response.ok) {
        alert('Applet archived successfully!');
      } else {
        alert('Failed to archive applet.');
      }
    })
    .catch(error => {
      console.error('Error:', error);
      alert('Failed to archive applet.');
    });
  }
}