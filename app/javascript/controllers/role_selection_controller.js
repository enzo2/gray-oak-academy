import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["teacherCode"]

  connect() {
    this.toggleTeacherCode();
  }

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
