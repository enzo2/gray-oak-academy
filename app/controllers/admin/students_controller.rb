module Admin
  class StudentsController < Admin::BaseController
    before_action :set_student, only: [ :show, :adopt, :unadopt, :enroll, :unenroll ]
    before_action :set_enrollment_data, only: [ :show, :enroll, :unenroll ]
    before_action :set_students_nav, only: [ :index, :show ]

    def index
      @student = nil
    end

    def show
      # Perform verification that the course reports were generated, in case the job failed originally
      @completed_enrollments.each do |enrollment|
        enrollment.course_report_check
      end
    end

    def adopt
      if @student.teacher.nil?
        @student.update(teacher: current_user)
        set_students_nav
        flash.now[:success] = "Student adopted successfully."
        respond_to do |format|
          format.turbo_stream
          format.html { redirect_to admin_students_path, status: :see_other }
        end
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
      respond_to do |format|
        format.turbo_stream { render :reload_dashboard }
        format.html { redirect_to admin_student_path(@student), status: :see_other }
      end
    end

    def unenroll
      enrollment = @student.enrollments.find_by(course_id: params[:course_id])
      enrollment&.destroy
      respond_to do |format|
        format.turbo_stream { render :reload_dashboard }
        format.html { redirect_to admin_student_path(@student), status: :see_other }
      end
    end

    private

    def set_student
      @student = User.find(params[:id])
    end

    def set_students_nav
      @my_students = current_user.students.order(last_name: :asc)
      @other_students = User.role_student.where.not(id: @my_students.pluck(:id))
    end

    def set_enrollment_data
      @active_enrollments = @student.enrollments.in_progress
      @completed_enrollments = @student.enrollments.completed
      @orphaned_reports = @student.student_reports.orphaned.order(created_at: :desc)
    end
  end
end
