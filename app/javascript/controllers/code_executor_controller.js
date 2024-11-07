import { Controller } from "@hotwired/stimulus"

/*
  LLM Instructions:
  When generating code responses, follow these guidelines:
  Format non-executable code or snippets using markdown as usual.
  You can create applets. Mark JavaScript as executable by wrapping it in a <pre data-executable> tag, without any <code> tag,
  and close it with //EOB</pre> to indicate the end of the code. The EOB marker is necessary to avoid executing the code prematurely.
  Additional <pre> tag attributes for controlling execution:
  - data-hidden="true" to initially hide the code with a toggle button.
  - data-auto-run="true" to execute immediately without showing a Run button.
  - data-render-target="chalkboard" to render in the chalkboard instead of inline.
  Inline applets will be executed within an iframe with about 400px of height and 550px width within the conversation.
  By default, there is a light background with dark text.#{' '}
  This iframe contains a <div id="sandbox">, available as the sandbox object.
  Use the sandbox object to append any created elements. For example:
    const slider = document.createElement('input');
    sandbox.appendChild(slider);
  Console is also sandboxed. Use console.log() for any output that should be displayed as text to the user.
  You can use APIs like Fullscreen, Promise, Audio, Canvas, WebGL, Web Animations, etc.
  Do not access the microphone or camera.
*/

export default class extends Controller {
  static targets = ["chalkboard", "message"]

  connect() {
  }

  // Called when a new message is added to the conversation.
  messageTargetConnected(messageElement) {
    this.setupExecutableBlocks(messageElement);
    console.log("messageTargetConnected");
  }

  setupExecutableBlocks(element) {
    const executableBlocks = element.querySelectorAll("pre[data-executable]");

    executableBlocks.forEach(block => {
      const endOfBlock = block.outerHTML.slice(-30).trim();
      if (!endOfBlock.endsWith('//EOB</pre>')) return;
      
      const config = {
        hidden: block.dataset.hidden === 'true',
        autoRun: block.dataset.autoRun === 'true',
        renderTarget: block.dataset.renderTarget || 'inline'
      };

      this.setupBlock(block, config);
    });
  }

  setupBlock(block, config) {

    const container = this.createContainer(block);
    
    if (config.hidden) {
      this.setupHiddenBlock(block, container);
    }

    const button = this.createRunButton(block, config.renderTarget);
    container.appendChild(button);

    if (config.renderTarget === 'inline') {
      const output = this.createOutputDiv();
      container.appendChild(output);
    }

    if (config.autoRun) {
      this.executeCode(block, config.renderTarget);
    }
  }

  createContainer(block) {
    const container = document.createElement("div");
    container.className = "relative";
    block.parentNode.insertBefore(container, block);
    container.appendChild(block);
    return container;
  }

  setupHiddenBlock(block, container) {
    block.style.display = 'none';
    const toggleBtn = this.createToggleButton(block);
    container.insertBefore(toggleBtn, block);
  }

  createToggleButton(block) {
    const toggleBtn = document.createElement("button");
    toggleBtn.textContent = "Show Code";
    toggleBtn.className = "px-3 py-1 text-sm bg-blue-500 text-white rounded hover:bg-blue-600";
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
    button.className = "px-3 py-1 text-sm bg-green-500 text-white rounded hover:bg-green-600 ml-2";
    button.addEventListener("click", () => this.executeCode(block, renderTarget));
    return button;
  }

  createOutputDiv() {
    const output = document.createElement("div");
    output.className = "mt-2 p-2 bg-gray-100 text-black rounded";
    output.style.display = "none";
    return output;
  }

  executeCode(block, renderTarget = 'inline') {
    if (block.querySelector("code")) {
      console.error("Execution cancelled: <code> tag found inside <pre data-executable>");
      return;
    }

    const code = block.textContent;
    const output = this.getOutputElement(block, renderTarget);
    if (!output) return;

    output.innerHTML = ''; // Clear previous content
    const iframe = this.createSandboxedIframe(renderTarget);
    output.appendChild(iframe);

    const iframeContent = this.prepareIframeContent(code);
    iframe.srcdoc = iframeContent;
  }

  getOutputElement(block, renderTarget) {
    if (renderTarget === 'chalkboard') {
      const output = this.chalkboardTarget;
      if (!output) {
        console.error("Chalkboard element not found");
        return null;
      }
      output.style.display = "block";
      output.innerHTML = "";
      return output;
    } else {
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
  }
}
