module Admin
  class CoursesController < Admin::BaseController
    before_action :set_course, only: [
      :edit, :update, :destroy, :generate_outline, :archive, :unarchive,
      :start_outline_research, :outline_research_input, :submit_outline_research_inputs, :resume_outline_research, :undo_outline_research_changes
    ]
    before_action :authorize_course_generation_access!, only: [ :start_outline_research, :outline_research_input, :submit_outline_research_inputs, :resume_outline_research, :undo_outline_research_changes ]
    before_action :ensure_outline_research_review_page_available!, only: [ :outline_research_input ]
    before_action :ensure_outline_research_input_stage!, only: [ :submit_outline_research_inputs, :resume_outline_research ]

    def index
      @active_courses =   Course.status_active.where(teacher: current_user).order(created_at: :desc)
      @archived_courses = Course.status_archived.where(teacher: current_user).order(created_at: :desc)
    end

    def new
      @course = Course.new
    end

    def create
      @course = Course.new(course_params)
      @course.teacher = current_user

      if @course.save
        respond_to do |format|
          format.turbo_stream
        end
      else
        respond_to do |format|
          format.turbo_stream { render :create, status: :unprocessable_content }
        end
      end
    end

    def edit
    end

    def update
      if @course.update(course_params)
        redirect_to admin_courses_path, status: :see_other
      else
        respond_to do |format|
          format.html { render :edit, status: :unprocessable_content }
        end
      end
    end

    def destroy
      @course.destroy
      redirect_to admin_courses_path, status: :see_other
    end

    # POST /admin/courses/:id/archive
    def archive
      @course.update!(status: :archived)
      redirect_to admin_courses_path, status: :see_other
    end

    # POST /admin/courses/:id/unarchive
    def unarchive
      @course.update!(status: :active)
      redirect_to admin_courses_path, status: :see_other
    end

    # POST /admin/courses/:id/generate_outline
    def generate_outline
      # Enqueue the background job
      GenerateCourseOutlineJob.perform_later(@course, current_user)

      respond_to do |format|
        format.turbo_stream
        format.html do
          flash[:success] = "Course outline generation started. Refresh in about a minute."
          redirect_to admin_courses_path, status: :see_other
        end
      end
    end

    # POST /admin/courses/:id/start_outline_research
    def start_outline_research
      result = CourseOutlineResearchAsyncService.new(
        course: @course,
        current_user: current_user,
        source: "course_edit_page"
      ).enqueue_start

      if result[:ok]
        redirect_to edit_admin_course_path(@course), notice: result[:message], status: :see_other
      else
        redirect_to edit_admin_course_path(@course), alert: result[:message], status: :see_other
      end
    end

    # GET /admin/courses/:id/outline_research_input
    def outline_research_input
      @read_only_report_mode = !@course.outline_research_input_open?
      @questions = Array(@course.outline_guidance_questions).select { |q| q.is_a?(Hash) && q["id"].to_s.present? }
      @source_anchors = Array(@course.outline_research_hash["source_anchors"]).map { |anchor| anchor.is_a?(Hash) ? anchor : {} }
    end

    # PATCH /admin/courses/:id/submit_outline_research_inputs
    def submit_outline_research_inputs
      update_outline_research_inputs!(@course)
      redirect_to outline_research_inputs_redirect_path(@course), notice: "Saved research responses and source-anchor decisions.", status: :see_other
    rescue StandardError => e
      redirect_to outline_research_inputs_error_redirect_path(@course), alert: "Failed to save research inputs: #{e.message}", status: :see_other
    end

    # PATCH|POST /admin/courses/:id/resume_outline_research
    def resume_outline_research
      update_outline_research_inputs!(@course)
      permission_granted = ActiveModel::Type::Boolean.new.cast(params[:allow_agent_modifications])

      result = CourseOutlineResearchAsyncService.new(
        course: @course,
        current_user: current_user,
        source: "course_edit_page"
      ).enqueue_resume(permission_granted: permission_granted)

      if result[:ok]
        redirect_to edit_admin_course_path(@course), notice: result[:message], status: :see_other
      else
        redirect_to outline_research_inputs_error_redirect_path(@course), alert: result[:message], status: :see_other
      end
    rescue StandardError => e
      redirect_to outline_research_inputs_error_redirect_path(@course), alert: "Failed to resume outline research: #{e.message}", status: :see_other
    end

    # POST /admin/courses/:id/undo_outline_research_changes
    def undo_outline_research_changes
      result = UndoCourseResearchChangesService.new(course: @course).undo!

      if result[:ok]
        redirect_to edit_admin_course_path(@course), notice: result[:message], status: :see_other
      else
        redirect_to edit_admin_course_path(@course), alert: result[:message], status: :see_other
      end
    end

    private

    def set_course
      @course = Course.find(params[:id])
    end

    def course_params
      # Extract the keys and values for outline
      outline_topics = params[:course].delete(:outline_topics) || []
      outline_details = params[:course].delete(:outline_details) || []

      # Zip the topics and details into an array of arrays [ [topic1, details1], [topic2, details2], ...
      # And then map it to an array of hashes [ { topic1 => details1 }, { topic2 => details2 }, ... ]
      outline = outline_topics.zip(outline_details).map { |topic, details| { topic => details } }

      params.require(:course).permit(:title, :summary, :grade_level).tap do |whitelisted|
        whitelisted[:outline] = outline
      end
    end

    def authorize_course_generation_access!
      return if current_user.role_superuser?
      raise ActiveRecord::RecordNotFound unless @course.teacher_id == current_user.id
    end

    def ensure_outline_research_input_stage!
      return if @course.outline_research_input_open?

      redirect_to edit_admin_course_path(@course), alert: "Outline research input is only available while awaiting teacher input or after a failed apply run.", status: :see_other
    end

    def ensure_outline_research_review_page_available!
      return if @course.outline_research_review_page_available?

      redirect_to edit_admin_course_path(@course), alert: "Outline research review is only available while awaiting teacher input, after a failed apply run, or when a guidance report exists.", status: :see_other
    end

    def update_outline_research_inputs!(course)
      updates = {}

      choices = params[:question_choices]
      has_choices = choices.respond_to?(:to_unsafe_h)
      has_additional_comments = params.key?(:additional_comments)
      if has_choices || has_additional_comments
        merged_answers = (course.outline_guidance_answers.is_a?(Hash) ? course.outline_guidance_answers.deep_dup : {})

        if has_choices
          choice_hash = choices.to_unsafe_h
          other_hash = params[:question_other_text].respond_to?(:to_unsafe_h) ? params[:question_other_text].to_unsafe_h : {}

          choice_hash.each do |question_id, raw_choice|
            question_key = question_id.to_s
            choice = raw_choice.to_s.upcase
            other_text = other_hash[question_key].to_s.strip
            payload = build_question_answer(choice: choice, other_text: other_text)

            if payload.present?
              merged_answers[question_key] = payload
            else
              merged_answers.delete(question_key)
            end
          end
        end

        if has_additional_comments
          additional_comments = params[:additional_comments].to_s.strip
          if additional_comments.present?
            merged_answers[Course::OUTLINE_GUIDANCE_ADDITIONAL_COMMENTS_KEY] = additional_comments
          else
            merged_answers.delete(Course::OUTLINE_GUIDANCE_ADDITIONAL_COMMENTS_KEY)
          end
        end

        updates[:outline_guidance_answers] = merged_answers
      end

      if params[:approve_all].to_s == "1" || params[:source_anchor_decisions].present?
        research = course.outline_research_hash.deep_dup
        decisions = params[:source_anchor_decisions].respond_to?(:to_unsafe_h) ? params[:source_anchor_decisions].to_unsafe_h : {}

        research["source_anchors"] = Array(research["source_anchors"]).map.with_index do |anchor, idx|
          anchor_hash = anchor.is_a?(Hash) ? anchor.deep_dup : {}
          desired_decision =
            if params[:approve_all].to_s == "1"
              "approved"
            else
              decisions[idx.to_s].to_s
            end

          if %w[pending approved rejected].include?(desired_decision)
            anchor_hash["decision"] = desired_decision
          end
          anchor_hash
        end
        updates[:outline_research] = research
      end

      course.update!(updates) if updates.present?
    end

    def build_question_answer(choice:, other_text:)
      case choice
      when "A", "B", "C"
        { "choice" => choice }
      when "OTHER"
        return nil if other_text.blank?

        { "choice" => "OTHER", "other_text" => other_text }
      else
        nil
      end
    end

    def outline_research_inputs_redirect_path(course)
      return edit_admin_course_path(course) unless params[:from_outline_research_input].to_s == "1"
      outline_research_input_admin_course_path(course)
    end

    def outline_research_inputs_error_redirect_path(course)
      return edit_admin_course_path(course) unless params[:from_outline_research_input].to_s == "1"
      outline_research_input_admin_course_path(course)
    end
  end
end
