module Admin
  class StudentsController < AdminController
    def index
      @students = User.role_student.all
    end
  end
end
