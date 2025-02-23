module Admin
  class StudentsController < ApplicationController
    before_action :require_admin
    before_action :set_student, only: [ :show, :adopt, :unadopt, :enroll, :unenroll ]

    def index
      @my_students = current_user.students.order(last_name: :asc)
      @other_students = User.role_student.where.not(id: @my_students.pluck(:id))
    end

    def show
      @active_enrollments = @student.enrollments.in_progress
      @completed_enrollments = @student.enrollments.completed

      # Perform verification that the course reports were generated, in case the job failed originally
      @completed_enrollments.each do |enrollment|
        enrollment.course_report_check
      end
    end

    def adopt
      if @student.teacher.nil?
        @student.update(teacher: current_user)
        redirect_to admin_students_path
      else
        flash[:alert] = "Student already has a teacher."
        respond_to do |format|
          format.turbo_stream
        end
      end
    end

    def unadopt
      @student.update(teacher: nil)
      redirect_to admin_students_path
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
  end
end
