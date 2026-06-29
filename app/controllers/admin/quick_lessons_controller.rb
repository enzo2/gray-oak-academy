module Admin
  class QuickLessonsController < Admin::BaseController
    before_action :set_quick_lesson, only: [ :edit, :update, :archive, :unarchive, :destroy ]

    def index
      @quick_lessons = current_user.taught_courses
                                   .quick_lessons
                                   .includes(:students, lessons: :lesson_plan)
                                   .order(created_at: :desc)
      @active_quick_lessons = @quick_lessons.select(&:status_active?)
      @archived_quick_lessons = @quick_lessons.reject(&:status_active?)
    end

    def new
      @quick_lesson = current_user.taught_courses.build(kind: "quick_lesson")
      @lesson = @quick_lesson.lessons.build
      set_assignable_students
    end

    def edit
      @lesson = @quick_lesson.lessons.first_or_initialize
      set_assignable_students
    end

    def create
      set_assignable_students
      @quick_lesson = current_user.taught_courses.build(quick_lesson_course_params)
      @quick_lesson.kind = "quick_lesson"
      @lesson = @quick_lesson.lessons.build(quick_lesson_lesson_params)
      assigned_students = @assignable_students.where(id: selected_student_ids)

      Course.transaction do
        @quick_lesson.save!
        @lesson.save!
        assigned_students.each { |student| @quick_lesson.enrollments.create!(student: student) }
      end

      redirect_to edit_admin_course_lesson_lesson_plan_path(@quick_lesson, @lesson),
                  notice: "Quick lesson created. Add or generate the lesson plan, then publish when ready.",
                  status: :see_other
    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_content
    end

    def update
      set_assignable_students
      @lesson = @quick_lesson.lessons.first_or_initialize
      assigned_students = @assignable_students.where(id: selected_student_ids)

      Course.transaction do
        @quick_lesson.update!(quick_lesson_course_params)
        @lesson.update!(quick_lesson_lesson_params)
        @quick_lesson.enrollments.where.not(student: assigned_students).destroy_all
        assigned_students.find_each do |student|
          @quick_lesson.enrollments.find_or_create_by!(student: student)
        end
      end

      redirect_to admin_quick_lessons_path,
                  notice: "Quick lesson updated.",
                  status: :see_other
    rescue ActiveRecord::RecordInvalid
      render :edit, status: :unprocessable_content
    end

    def archive
      @quick_lesson.update!(status: :archived)
      redirect_to admin_quick_lessons_path, status: :see_other
    end

    def unarchive
      @quick_lesson.update!(status: :active)
      redirect_to admin_quick_lessons_path, status: :see_other
    end

    def destroy
      Course.transaction do
        @quick_lesson.enrollments.destroy_all
        @quick_lesson.destroy!
      end

      redirect_to admin_quick_lessons_path, status: :see_other
    end

    private

    def set_quick_lesson
      @quick_lesson = current_user.taught_courses.quick_lessons.find(params[:id])
    end

    def set_assignable_students
      @assignable_students = current_user.students.order(:last_name, :first_name)
    end

    def quick_lesson_params
      params.require(:quick_lesson).permit(
        :title,
        :grade_level,
        :goals,
        :approx_duration_min,
        student_ids: []
      )
    end

    def quick_lesson_course_params
      {
        title: quick_lesson_params[:title],
        summary: quick_lesson_params[:goals],
        grade_level: quick_lesson_params[:grade_level]
      }
    end

    def quick_lesson_lesson_params
      quick_lesson_params.slice(:title, :goals, :approx_duration_min)
    end

    def selected_student_ids
      Array(quick_lesson_params[:student_ids]).reject(&:blank?)
    end
  end
end
