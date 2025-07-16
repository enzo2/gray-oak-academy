import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["icon", "content"];
  static values = {
    animate: { type: Boolean, default: true },
  };

  connect() {
    this.isAnimating = false;
    this.onTransitionEndBound = this.onTransitionEnd.bind(this);

    this.element.querySelectorAll('button[data-action="click->tree-view#toggle"]').forEach((button) => {
      this.updateIcon(button);
    });

    this.addKeyboardListeners();
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.handleKeydownBound);
    this.contentTargets.forEach((content) => {
      content.removeEventListener("transitionend", this.onTransitionEndBound);
    });
  }

  addKeyboardListeners() {
    this.handleKeydownBound = this.handleKeydown.bind(this);
    this.element.addEventListener("keydown", this.handleKeydownBound);
  }

  handleKeydown(event) {
    const triggers = Array.from(this.element.querySelectorAll('button[data-action="click->tree-view#toggle"]'));
    const currentIndex = triggers.indexOf(document.activeElement);
    if (currentIndex === -1) return;

    let nextFocusable;

    switch (event.key) {
      case "ArrowUp":
        event.preventDefault();
        nextFocusable = this.findPreviousFocusable(triggers, currentIndex);
        nextFocusable?.focus();
        break;
      case "ArrowDown":
        event.preventDefault();
        nextFocusable = this.findNextFocusable(triggers, currentIndex);
        nextFocusable?.focus();
        break;
      case "Enter":
      case " ":
        event.preventDefault();
        triggers[currentIndex].click();
        break;
    }
  }

  findNextFocusable(elements, startIndex) {
    let index = startIndex;
    do {
      index = (index + 1) % elements.length;
      if (!this.isElementHidden(elements[index])) {
        return elements[index];
      }
    } while (index !== startIndex);
    return null;
  }

  findPreviousFocusable(elements, startIndex) {
    let index = startIndex;
    do {
      index = (index - 1 + elements.length) % elements.length;
      if (!this.isElementHidden(elements[index])) {
        return elements[index];
      }
    } while (index !== startIndex);
    return null;
  }

  isElementHidden(element) {
    return element.offsetParent === null;
  }

  toggle(event) {
    if (this.isAnimating) return;

    const button = event.currentTarget;
    const content = document.getElementById(button.getAttribute("aria-controls"));
    const isOpen = button.getAttribute("aria-expanded") === "true";

    button.setAttribute("aria-expanded", String(!isOpen));
    content.setAttribute("data-state", isOpen ? "closed" : "open");

    if (this.animateValue) {
      this.isAnimating = true;
      content.removeEventListener("transitionend", this.onTransitionEndBound);
      content.addEventListener("transitionend", this.onTransitionEndBound);

      if (isOpen) {
        this.close(content);
      } else {
        this.open(content);
      }
    } else {
      content.hidden = isOpen;
    }

    this.updateIcon(button);
  }

  open(content) {
    content.hidden = false;
    const height = content.scrollHeight;
    content.style.height = "0";
    content.style.transition = "height 300ms ease-out";
    requestAnimationFrame(() => {
      content.style.height = `${height}px`;
    });
  }

  close(content) {
    const height = content.scrollHeight;
    content.style.height = `${height}px`;
    content.style.transition = "height 300ms ease-out";
    requestAnimationFrame(() => {
      content.style.height = "0";
    });
  }

  onTransitionEnd(event) {
    const content = event.target;
    const isOpen = content.getAttribute("data-state") === "open";

    if (!isOpen) {
      content.hidden = true;
    }

    content.style.height = "";
    content.style.transition = "";
    this.isAnimating = false;
  }

  updateIcon(button) {
    const icon = button.querySelector('[data-tree-view-target="icon"]');
    if (!icon) return;

    const isOpen = button.getAttribute("aria-expanded") === "true";
    icon.innerHTML = isOpen ? this.openFolderSvg : this.closedFolderSvg;
    if (isOpen) {
      icon.classList.add("folder-open");
    } else {
      icon.classList.remove("folder-open");
    }
  }

  get openFolderSvg() {
    return `<svg xmlns="http://www.w3.org/2000/svg" class="w-full h-full" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
      <path d="M5,14.75h-.75c-1.105,0-2-.895-2-2V4.75c0-1.105,.895-2,2-2h1.825c.587,0,1.144,.258,1.524,.705l1.524,1.795h4.626c1.105,0,2,.895,2,2v1"></path>
      <path d="M16.148,13.27l.843-3.13c.257-.953-.461-1.89-1.448-1.89H6.15c-.678,0-1.272,.455-1.448,1.11l-.942,3.5c-.257,.953,.461,1.89,1.448,1.89H14.217c.904,0,1.696-.607,1.931-1.48Z"></path>
    </svg>`;
  }

  get closedFolderSvg() {
    return `<svg xmlns="http://www.w3.org/2000/svg" class="w-full h-full" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
      <path d="M13.75,5.25c1.105,0,2,.895,2,2v5.5c0,1.105-.895,2-2,2H4.25c-1.105,0-2-.895-2-2V4.75c0-1.105,.895-2,2-2h1.825c.587,0,1.144,.258,1.524,.705l1.524,1.795h4.626Z"></path>
    </svg>`;
  }
}
