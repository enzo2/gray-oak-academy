module Admin
  class StudentsController < Admin::BaseController
    before_action :set_student, only: [ :show, :adopt, :unadopt, :enroll, :unenroll ]
    before_action :set_students_nav, only: [ :index, :show ]

    def index
    end

    def show
      @active_enrollments = @student.enrollments.in_progress
      @completed_enrollments = @student.enrollments.completed

      # Perform verification that the course reports were generated, in case the job failed originally
      @completed_enrollments.each do |enrollment|
        enrollment.course_report_check
      end

      @orphaned_reports = @student.student_reports.orphaned.order(created_at: :desc)
    end

    def adopt
      if @student.teacher.nil?
        @student.update(teacher: current_user)
        flash[:success] = "Student adopted successfully."
        redirect_to admin_students_path, status: :see_other
      else
        flash.now[:error] = "Student already has a teacher."
        render :adopt, status: :unprocessable_entity
      end
    end

    def unadopt
      @student.update(teacher: nil)
      flash[:success] = "Student unadopted successfully."
      redirect_to admin_students_path, status: :see_other
    end

    def enroll
      course = Course.find(params[:course_id])
      @student.enrollments.create(course: course)
      redirect_to admin_student_path(@student)
    end

    def unenroll
      enrollment = @student.enrollments.find_by(course_id: params[:course_id])
      enrollment&.destroy
      redirect_to admin_student_path(@student)
    end

    private

    def set_student
      @student = User.find(params[:id])
    end

    def set_students_nav
      @my_students = current_user.students.order(last_name: :asc)
      @other_students = User.role_student.where.not(id: @my_students.pluck(:id))
    end
  end
end
