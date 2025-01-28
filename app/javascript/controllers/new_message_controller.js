import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fileInput", "urlInput", "previewArea", "contentField", "imagesData", "menu", "urlDialog", "submitButton", "submitSpinner", "submitIcon"];
  static MAX_IMAGES = 4;

  connect() {
    //console.log("New message controller connected")
    this.images = []
    this.menuTarget.addEventListener('sl-select', this.handleMenuSelect.bind(this))
    this.contentFieldTarget.addEventListener('paste', this.paste.bind(this))
   
  }

  handleMenuSelect(event) {
    //console.log("Handling menu select", event.detail.item.value)
    if (event.detail.item.value === 'file') {
      this.fileInputTarget.click()
    } else if (event.detail.item.value === 'url') {
      this.urlDialogTarget.show()
    }
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

  handleUrl(event) {
    //console.log("Handling URL input")
    if (event.key === 'Enter') {
      this.handleUrlInput()
    }
  }

  submitUrl() {
    this.handleUrlInput()
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
      //console.log("Validating image URL through proxy")
      const proxyUrl = `/proxy/image?url=${encodeURIComponent(url)}`
      const response = await fetch(proxyUrl, { method: 'HEAD' })
      //console.log(response.headers.get('Content-Type'))
      const contentType = response.headers.get('Content-Type').split(';')[0]
      //console.log("Content-Type:", contentType)
      if (!["image/png", "image/jpeg", "image/webp"].includes(contentType)) {
        alert("Invalid image type. Only PNG, JPEG, and WebP are allowed.")
        return
      }
      this.addImage({ url: url, type: contentType })
    } catch (error) {
      alert("Failed to validate image URL. Please ensure the URL is accessible.")
   
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

  addImage(image) {
    //console.log("Adding image", image)
    if (image.url) {
      this.images.push(image)
      this.updateImagesData()
      this.updatePreview()
    } else {
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
      previewElement.classList.add('mr-2', 'relative')
      if (image.url) {
        previewElement.innerHTML = `
          <img src="${image.url}" class="h-20 w-20 object-cover rounded" alt="Image ${index + 1}">
          <sl-icon-button name="x"
            data-action="click->new-message#removeImage" 
            data-index="${index}" 
            class="absolute top-0 right-0 bg-gray-500 rounded-md [&::part(base)]:p-[4px] text-white">
          </sl-icon-button>`
      } else {
        previewElement.innerHTML = `
          <img src="${image.data}" class="h-20 w-20 object-cover rounded" alt="Image ${index + 1}">
          <span class="block text-xs mt-1">${image.name.length > 15 ? `${image.name.slice(0, 10)}...${image.name.slice(-5)}` : image.name}</span>
          <sl-icon-button name="x"
            data-action="click->new-message#removeImage" 
            data-index="${index}" 
            class="absolute top-0 right-0 bg-gray-500 rounded-md [&::part(base)]:p-[4px] text-white">
          </sl-icon-button>`
      }
      this.previewAreaTarget.appendChild(previewElement)
    })
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
    this.submitButtonTarget.disabled = true
    this.element.requestSubmit(); // Submit the form
    this.submitIconTarget.classList.add("hidden")
    this.submitSpinnerTarget.classList.remove("hidden")
  }
/*
  resetSubmit() {
    this.submitButtonTarget.disabled = false
    this.submitIconTarget.classList.remove("hidden")
    this.submitSpinnerTarget.classList.add("hidden")
  }
*/
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
}
