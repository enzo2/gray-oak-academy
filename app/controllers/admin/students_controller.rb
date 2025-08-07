module Admin
  class StudentsController < Admin::BaseController
    before_action :require_superuser, only: [ :destroy ]
    before_action :set_student, only: [ :show, :adopt, :unadopt, :enroll, :unenroll, :destroy ]
    before_action :set_enrollment_data, only: [ :show, :enroll, :unenroll ]
    before_action :set_students_nav, only: [ :index, :show ]
    before_action :require_own_student, only: [ :show, :unadopt, :enroll, :unenroll ]

    # POST /admin/students/new
    def new_student
      params = student_params.except(:adopt_student).merge(signup_code: ENV["STUDENT_SIGNUP_CODE"])
      if current_user.role_teacher? && student_params[:adopt_student] == "1"
        params[:teacher] = current_user
      end
      @student = User.new(params)
      if @student.save
        flash[:success] = "Student account created."
        if @student.teacher.present?
          redirect_to admin_student_path(@student)
        else
          redirect_to admin_students_path, status: :see_other
        end
      else
        flash.now[:error] = @student.errors.full_messages.to_sentence
        respond_to do |format|
          format.turbo_stream { render "update_new_student_modal", status: :unprocessable_entity }
          format.html { redirect_to admin_students_path, status: :unprocessable_entity }
        end
      end
    end

    def index
      @student = nil
    end

    def show
      # Perform verification that the course reports were generated, in case the job failed originally
      @active_enrollments.each do |enrollment|
        enrollment.course_report_check if enrollment.completed?
      end
    end

    def adopt
      if @student.update(teacher: current_user)
        flash[:success] = "Student adopted successfully."
        redirect_to admin_student_path(@student), status: :see_other
      else
        flash[:error] = @student.errors.full_messages.to_sentence
        redirect_to admin_students_path, status: :unprocessable_content
      end
    end

    def unadopt
      @student.update!(teacher: nil)
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

    def destroy
      # Only available to superusers. This is a highly destructive action.
      @student.destroy!
      flash[:success] = "Student deleted successfully."
      redirect_to admin_students_path, status: :see_other
    end

    private

    def require_own_student
      # Superusers can access any student. Admins can only access their own students.
      unless current_user.role_superuser? || current_user.students.include?(@student)
        flash[:warning] = "You are not that student's teacher."
        redirect_to admin_students_path
      end
    end

    def student_params
      params.require(:user).permit(:first_name, :last_name, :email, :password, :password_confirmation, :adopt_student)
    end

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
