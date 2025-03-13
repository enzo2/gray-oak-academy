import { Controller } from "@hotwired/stimulus"

// This controller is used to show/hide the teacher code input field based on the selected role
// It also listens for the `turbo:render` event to re-apply the logic when the page is re-rendered, e.g. if errors are displayed
export default class extends Controller {
  static targets = ["teacherCode"]

  initialize() {
    this.toggleTeacherCodeBound = this.toggleTeacherCode.bind(this);
  }

  connect() {
    this.toggleTeacherCode();
    document.addEventListener('turbo:render', this.toggleTeacherCodeBound);
  }

  disconnect() {
    document.removeEventListener('turbo:render', this.toggleTeacherCodeBound);
  }

  toggleTeacherCode() {
    const isTeacher = this.element.querySelector('input[value="admin"]:checked') !== null;
    
    if (isTeacher) {
      this.teacherCodeTarget.classList.remove('hidden');
    } else {
      this.teacherCodeTarget.classList.add('hidden');
    }
  }
}
