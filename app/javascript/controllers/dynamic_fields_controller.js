import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["template", "container"]

  connect() {
    if (this.containerTarget.children.length === 0) {
      this.addField()
    }
  }

  addField() {
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, new Date().getTime().toString())
    this.containerTarget.insertAdjacentHTML('beforeend', content)
  }

  removeField(event) {
    const field = event.target.closest('.nested-fields')
    if (this.containerTarget.children.length > 1) {
      field.remove()
    }
  }
}