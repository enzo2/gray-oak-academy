module Admin
  class CoursesController < Admin::BaseController
    before_action :set_course, only: [
      :edit, :update, :destroy, :generate_outline, :archive, :unarchive,
      :start_outline_research, :outline_research_input, :submit_outline_research_inputs, :resume_outline_research, :convert_source_anchor_to_resource, :undo_outline_research_changes
    ]
    before_action :authorize_course_generation_access!, only: [ :start_outline_research, :outline_research_input, :submit_outline_research_inputs, :resume_outline_research, :convert_source_anchor_to_resource, :undo_outline_research_changes ]
    before_action :ensure_outline_research_review_page_available!, only: [ :outline_research_input ]
    before_action :ensure_outline_research_input_stage!, only: [ :submit_outline_research_inputs, :resume_outline_research ]

    def index
      @active_courses =   Course.full_courses.status_active.where(teacher: current_user).order(created_at: :desc)
      @archived_courses = Course.full_courses.status_archived.where(teacher: current_user).order(created_at: :desc)
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
      update_result = nil

      @course.with_lock do
        @course.reload
        return redirect_to(edit_admin_course_path(@course), alert: "Course edits are locked while outline research is in progress.", status: :see_other) if @course.outline_research_in_progress?

        update_result = @course.update(course_params)
      end

      if update_result
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

      @course.reload

      respond_to do |format|
        if result[:ok]
          format.turbo_stream do
            flash.now[:notice] = result[:message]
            render turbo_stream: course_edit_outline_research_streams(@course)
          end
          format.html { redirect_to edit_admin_course_path(@course), notice: result[:message], status: :see_other }
        else
          format.turbo_stream do
            flash.now[:alert] = result[:message]
            render turbo_stream: course_edit_outline_research_streams(@course), status: :unprocessable_content
          end
          format.html { redirect_to edit_admin_course_path(@course), alert: result[:message], status: :see_other }
        end
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

      if autosave_request?
        @course.reload
        render json: autosave_outline_research_payload(@course), status: :ok
      else
        redirect_to outline_research_inputs_redirect_path(@course), notice: "Saved research responses.", status: :see_other
      end
    rescue StandardError => e
      if autosave_request?
        render json: { ok: false, error: "Failed to save research inputs: #{e.message}" }, status: :unprocessable_content
      else
        redirect_to outline_research_inputs_error_redirect_path(@course), alert: "Failed to save research inputs: #{e.message}", status: :see_other
      end
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

    # POST /admin/courses/:id/convert_source_anchor_to_resource
    def convert_source_anchor_to_resource
      index = Integer(params[:source_anchor_index])
      anchor = @source_anchors.fetch(index)
      title = anchor["title"].to_s.strip.presence || "Source Anchor #{index + 1}"
      url = anchor["url"].to_s.strip
      resource_attrs = {
        teacher: current_user,
        category: "Source Anchor",
        description: title
      }

      if url.present?
        resource_attrs[:uri] = url
      else
        resource_attrs[:content] = source_anchor_text_content(anchor)
      end

      resource = Resource.new(resource_attrs)
      if resource.save
        redirect_to outline_research_input_admin_course_path(@course, anchor: "source-anchors"), notice: "Converted source anchor to resource.", status: :see_other
      else
        redirect_to outline_research_input_admin_course_path(@course, anchor: "source-anchors"), alert: "Failed to convert source anchor: #{resource.errors.full_messages.to_sentence}", status: :see_other
      end
    rescue ArgumentError, TypeError, IndexError
      redirect_to outline_research_input_admin_course_path(@course, anchor: "source-anchors"), alert: "Source anchor was not found.", status: :see_other
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
      @course = authorized_course_scope.full_courses.find(params[:id])
      @source_anchors = Array(@course.outline_research_hash["source_anchors"]).map { |anchor| anchor.is_a?(Hash) ? anchor : {} }
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

      message = "Outline research input is only available while awaiting teacher input or after a failed apply run."
      if autosave_request?
        render json: { ok: false, error: message }, status: :conflict
      else
        redirect_to edit_admin_course_path(@course), alert: message, status: :see_other
      end
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

    def source_anchor_text_content(anchor)
      excerpt = anchor["excerpt"].to_s.strip
      highlights = Array(anchor["highlights"]).map(&:to_s).map(&:strip).reject(&:blank?)
      notes = anchor["notes"].to_s.strip

      segments = []
      segments << "Excerpt:\n#{excerpt}" if excerpt.present?
      segments << "Highlights:\n#{highlights.map { |item| "- #{item}" }.join("\n")}" if highlights.any?
      segments << "Notes:\n#{notes}" if notes.present?
      segments.join("\n\n").presence || "No additional source details were provided."
    end

    def autosave_request?
      ActiveModel::Type::Boolean.new.cast(params[:autosave]) || request.format.json?
    end

    def autosave_outline_research_payload(course)
      unanswered_count = course.unanswered_research_question_ids.size
      resumable_run = course.outline_research_resumable_run?
      {
        ok: true,
        unanswered_count: unanswered_count,
        ready_to_resume: resumable_run && unanswered_count.zero?,
        resumable_run: resumable_run
      }
    end

    def course_edit_outline_research_streams(course)
      [
        turbo_stream.update("flash_bar", partial: "shared/flash"),
        turbo_stream.replace(
          view_context.dom_id(course, :outline_research_panel),
          partial: "admin/courses/outline_research_panel_container",
          locals: { course: course }
        ),
        turbo_stream.replace(
          view_context.dom_id(course, :form),
          partial: "admin/courses/form",
          locals: { course: course }
        ),
        turbo_stream.replace(
          view_context.dom_id(course, :outline_research_snapshot),
          partial: "admin/courses/outline_research_snapshot_container",
          locals: { course: course }
        ),
        turbo_stream.replace(
          view_context.dom_id(course, :outline_research_lock_state),
          partial: "admin/courses/outline_research_lock_state",
          locals: { course: course }
        )
      ]
    end
  end
end
