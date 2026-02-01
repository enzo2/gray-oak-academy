import { Controller } from "@hotwired/stimulus"

// Handles the message form in LLM conversations
// Enables image uploads, URL image previews, pasting images, shift+enter for new lines, and form submission
export default class extends Controller {
  static targets = [
    "fileInput",
    "urlInput",
    "previewArea",
    "contentField",
    "imagesData",
    "imagesMenuButton",
    "imagesMenu",
    "urlDialog",
    "submitButton",
    "submitSpinner",
    "submitIcon",
    "helpText",
    "cameraMenuItem",
    "cameraButton"
  ];
  static values = { audioSetting: String };
  static MAX_IMAGES = 4;

  connect() {
    //console.log("New message controller connected")
    this.images = []
    this.boundHandleMenuSelect = this.handleMenuSelect.bind(this)
    this.imagesMenuTarget.addEventListener('sl-select', this.boundHandleMenuSelect)
    if (this.hasCameraMenuItemTarget) {
      this.cameraMenuItemTarget.classList.add("hidden")
    }
    if (this.hasCameraButtonTarget) {
      this.cameraButtonTarget.classList.add("hidden")
    }
    this.dispatch("camera-check", { bubbles: true })
  }

  /* It's annoying to autofocus on mobile since the keyboard pops up 
  async contentFieldTargetConnected() {
    await Promise.allSettled([
      customElements.whenDefined('sl-textarea')
    ]);
    //this.contentFieldTarget.focus()
  } */
    

  toggleSubmitButton() {
    //console.log("toggleSubmitButton")
    const hasContent = this.contentFieldTarget.value.trim() !== '' || this.images.length > 0;
    if (hasContent && this.audioSettingValue != 'only') { // Don't toggle if audio_only set, since the record button is always shown; there's no submit button
      this.submitIconTarget.classList.remove("hidden");
      this.helpTextTarget.classList.remove("hidden");
    } else {
      this.submitIconTarget.classList.add("hidden");
      this.helpTextTarget.classList.add("hidden");
    }
  }

  handleMenuSelect(event) {
    //console.log("Handling menu select", event.detail.item.value)
    if (event.detail.item.value === 'file') {
      this.fileInputTarget.click()
    } else if (event.detail.item.value === 'url') {
      this.urlDialogTarget.show()
    } else if (event.detail.item.value === 'camera') {
      this.openCamera()
    }
  }

  openCamera() {
    this.dispatch("camera-open", { bubbles: true })
  }
  
  canAddMoreImages() {
    if (this.images.length >= this.constructor.MAX_IMAGES) {
      alert(`You can only add up to ${this.constructor.MAX_IMAGES} images per message.`)
      return false
    }
    return true
  }

  handleFiles(event) {
    //console.log("Handling files")
    const files = Array.from(event.target.files)
    files.forEach(file => {
      if (!this.canAddMoreImages()) return
      if (!this.validateImage(file)) return
      this.addImage(file)
    })
    this.fileInputTarget.value = null
  }

  closeUrlDialog() {
    this.urlDialogTarget.hide();
  }

  async handleUrlInput() {
    const url = this.urlInputTarget.value
    if (!this.canAddMoreImages()) return
    
    if (!URL.canParse(url)) {
      alert("Invalid URL.")
      return
    }

    try {
      const proxyUrl = `/proxy/image?url=${encodeURIComponent(url)}`
      const response = await fetch(proxyUrl, { method: 'HEAD' })
      if (!response.ok) {
        alert("Failed to validate image URL. Please ensure the URL is accessible. Status: " + response.statusText + " (" + response.status + ")")
        return
      }
      const contentType = response.headers.get('Content-Type').split(';')[0]
      if (!["image/png", "image/jpeg", "image/webp"].includes(contentType)) {
        alert("Invalid image type. Only PNG, JPEG, and WebP are allowed.")
        return
      }
      this.addImage({ url: url, type: contentType })
    } catch (error) {
      alert("Failed to validate image URL. Please ensure the URL is correct. Error: " + error.message)
      return
    }

    this.urlInputTarget.value = ""
    this.urlDialogTarget.hide()
  }

  validateImage(file) {
    if (!["image/png", "image/jpeg", "image/webp"].includes(file.type)) {
      alert("Invalid image type. Only PNG, JPEG, and WebP are allowed.");
      return false
    }
    if (file.size > 5 * 1024 * 1024) { // 5MB limit
      alert("Image size must be less than 5MB.");
      return false
    }
    return true
  }

  // Adds an image to the images array and updates the preview
  // Supports both URL images and file uploads
  addImage(image) {
    //console.log("Adding image", image)
    if (image.url) {
      this.images.push(image)
      this.updateImagesData()
      this.updatePreview()
    } else {
      if (!this.validateImage(image)) return;
      const reader = new FileReader()
      reader.onload = (e) => {
        this.images.push({
          data: e.target.result,
          type: image.type,
          name: image.name
        })
        this.updateImagesData()
        this.updatePreview()
      }
      reader.readAsDataURL(image)
    }
  }

  // Handles screenshot event from chalkboard_controller
  addScreenshotFromEvent(event) {
    console.log("Adding screenshot from event", event);
    if (event && event.detail && event.detail.blob) {
      if (!this.canAddMoreImages()) return;
      const blob = event.detail.blob;
      const file = new File([blob], 'chalkboard.png', { type: blob.type || 'image/png' });
      this.addImage(file);
    }
  }

  addCameraPhoto(event) {
    const file = event?.detail?.file
    if (!file) return
    if (!this.canAddMoreImages()) return
    this.addImage(file)
  }

  setCameraAvailability(event) {
    const available = Boolean(event?.detail?.available)
    if (this.audioSettingValue === "only") {
      if (this.hasCameraMenuItemTarget) {
        this.cameraMenuItemTarget.classList.add("hidden")
      }
      if (this.hasCameraButtonTarget) {
        this.cameraButtonTarget.classList.toggle("hidden", !available)
      }
      return
    }

    if (this.hasCameraMenuItemTarget) {
      this.cameraMenuItemTarget.classList.toggle("hidden", !available)
    }
    if (this.hasCameraButtonTarget) {
      this.cameraButtonTarget.classList.add("hidden")
    }
  }

  updatePreview() {
    //console.log("Updating preview")
    this.previewAreaTarget.innerHTML = ""
    if (this.images.length === 0) {
      this.previewAreaTarget.classList.add("hidden")
    } else {
      this.previewAreaTarget.classList.remove("hidden")
    }
    this.images.forEach((image, index) => {
      // Create a div for each image preview and append it to the previewAreaTarget 
      const previewElement = document.createElement('div')
      previewElement.classList.add('relative')
      if (image.url) {
        previewElement.innerHTML = `
          <img src="${image.url}" class="h-16 w-16 sm:h-20 sm:w-20 object-cover rounded-sm" alt="Image ${index + 1}">
          <sl-icon-button name="x"
            data-action="click->new-message#removeImage" 
            data-index="${index}" 
            class="absolute top-0 right-0 bg-stone-500 rounded-md [&::part(base)]:p-[4px] text-white">
          </sl-icon-button>`
      } else {
        previewElement.innerHTML = `
          <img src="${image.data}" class="h-16 w-16 sm:h-20 sm:w-20 object-cover rounded-sm" alt="Image ${index + 1}">
          <span class="block text-xs mt-1 text-center max-w-[4.5rem]">${image.name.length > 15 ? `${image.name.slice(0, 10)}...${image.name.slice(-5)}` : image.name}</span>
          <sl-icon-button name="x"
            data-action="click->new-message#removeImage" 
            data-index="${index}" 
            class="absolute top-0 right-0 bg-stone-500 rounded-md [&::part(base)]:p-[4px] text-white">
          </sl-icon-button>`
      }
      this.previewAreaTarget.appendChild(previewElement)
    })
    this.toggleSubmitButton()
  }

  removeImage(event) {
    //console.log("Removing image")
    const button = event.target.closest('sl-icon-button')
    if (button) {
      const index = button.dataset.index
      this.images.splice(index, 1)
      this.updateImagesData()
      this.updatePreview()
    } else {
      console.error("Remove button not found")
    }
  }

  updateImagesData() {
    //console.log("Updating images data")
    const processedImages = this.images.map(image => {
      if (image.url) {
        return { 
          url: image.url,
          type: image.type
        }
      } else {
        return {
          data: image.data,
          type: image.type,
          name: image.name
        }
      }
    })
    this.imagesDataTarget.value = JSON.stringify(processedImages)
  }

  submit(e) {
    e.preventDefault();
    if (this.contentFieldTarget.value.trim() !== '' || this.images.length > 0) {
      //console.log("Submitting form")
      this.submitButtonTarget.disabled = true
      this.element.requestSubmit(); // Submit the form
      this.submitIconTarget.classList.add("hidden")
      this.submitSpinnerTarget.classList.remove("hidden")
      this.imagesMenuButtonTarget.classList.add("hidden");
    }
  }

  paste(event) {
    //console.log("Pasting image")
    const items = (event.clipboardData || event.originalEvent.clipboardData).items;
    for (const item of items) {
      if (item.type.indexOf("image") === 0) {
        if (!this.canAddMoreImages()) return
        if (!["image/png", "image/jpeg", "image/webp"].includes(item.type)) {
          alert("Invalid image type. Only PNG, JPEG, and WebP are allowed.")
          return
        }
        const file = item.getAsFile()
        this.addImage(file)
        event.preventDefault()
      }
    }
  }

  disconnect() {
    if (this.imagesMenuTarget && this.boundHandleMenuSelect) {
      this.imagesMenuTarget.removeEventListener('sl-select', this.boundHandleMenuSelect)
    }
  }
}
