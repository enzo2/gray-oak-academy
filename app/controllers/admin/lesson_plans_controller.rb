module Admin
  class LessonPlansController < Admin::BaseController
    before_action :set_lesson
    before_action :authorize_generation_access!, only: [ :generate_content, :propose_resources ]
    before_action :set_lesson_plan, only: [ :edit, :update, :destroy, :link_resource, :unlink_resource, :delete_resource, :new_resource, :generate_content, :propose_resources, :remove_suggested_resource ]

    def edit
      # Render the edit form for the lesson plan
    end

    def update
      if @lesson_plan.update(lesson_plan_params)
        flash[:success] = "Updated successfully."
        redirect_to edit_admin_course_lesson_lesson_plan_path(@lesson.course, @lesson), status: :see_other
      else
        flash[:error] = "Failed to update lesson plan."
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @lesson_plan.destroy
      redirect_target = @lesson.course.kind_quick_lesson? ? admin_quick_lessons_path : admin_course_lessons_path(@lesson.course)
      redirect_to redirect_target, status: :see_other
    end

    def link_resource
      @lesson_plan.save! if @lesson_plan.new_record?
      @resource = find_linkable_resource!
      @resource_linked = false

      if @lesson_plan.status_published? && @resource.approved == false
        flash.now[:warning] = "The lesson plan is published. If you want to link a pending resource, please change the lesson plan back to draft status."
      elsif !@lesson_plan.resources.exists?(id: @resource.id)
        @lesson_plan.resources << @resource
        @resource_linked = true
      end

      respond_to do |format|
        format.turbo_stream
      end
    end

    def unlink_resource
      @resource = find_linked_resource!
      if @resource.approved == false
        raise ActiveRecord::RecordNotFound unless can_destroy_resource?(@resource)

        @resource.destroy!
        @resource_deleted = true
      else
        @lesson_plan.resources.delete(@resource)
        @resource_deleted = false
      end
      @linked_resources_remaining = @lesson_plan.resources.exists?

      respond_to do |format|
        format.turbo_stream
      end
    end

    def delete_resource
      @resource = find_linked_resource!
      raise ActiveRecord::RecordNotFound unless can_destroy_resource?(@resource)

      @resource.destroy!
      @resource_deleted = true
      @linked_resources_remaining = @lesson_plan.resources.exists?

      respond_to do |format|
        format.turbo_stream
      end
    end

    def new_resource
      # Renders the form to create a new resource for the lesson plan
      # Persist the lesson plan so the form has an id to attach the resource
      @lesson_plan.save! if @lesson_plan.new_record?
      respond_to do |format|
        format.turbo_stream
      end
    end

    def generate_content
      propose_resources = ActiveModel::Type::Boolean.new.cast(params[:propose_resources])
      steering = normalize_generation_steering

      if steering[:error]
        flash.now[:warning] = steering[:error]
        set_generation_submit_header(queued: false)
        render :generate_content
        return
      end

      # Persist the lesson plan before generating content, since it may be new.
      @lesson_plan.save!

      result = LessonPlanAsyncGenerationService.new(
        lesson_plan: @lesson_plan,
        current_user: current_user,
        source: "lesson_plan_button"
      ).enqueue_generate_content(
        propose_resources: propose_resources,
        steering_guidance: steering[:guidance]
      )
      flash.now[:warning] = result[:message] unless result[:ok]
      set_generation_submit_header(queued: result[:ok])

      respond_to do |format|
        format.turbo_stream
      end
    end

    def propose_resources
      @lesson_plan.save! if @lesson_plan.new_record?
      result = LessonPlanAsyncGenerationService.new(
        lesson_plan: @lesson_plan,
        current_user: current_user,
        source: "lesson_plan_button"
      ).enqueue_propose_resources
      flash.now[:warning] = result[:message] unless result[:ok]

      respond_to do |format|
        format.turbo_stream
      end
    end

    def remove_suggested_resource
      index = params[:resource_index].to_i
      @lesson_plan.suggested_resources ||= []
      if index >= 0 && index < @lesson_plan.suggested_resources.length
        @lesson_plan.suggested_resources.delete_at(index)
        @lesson_plan.save!
      end
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.remove("suggested-resource-#{index}") }
        format.html { redirect_to edit_admin_course_lesson_lesson_plan_path(@lesson.course, @lesson) }
      end
    end

    private

    def set_lesson
      @course = authorized_course_scope.find(params[:course_id])
      @lesson = @course.lessons.find(params[:lesson_id])
    end

    def set_lesson_plan
      @lesson_plan = @lesson.lesson_plan || @lesson.build_lesson_plan
    end

    def lesson_plan_params
      # Extract `content_keys` and `content_values` from params, default to empty arrays if not present
      content_keys = params[:lesson_plan].delete(:content_keys) || []
      content_values = params[:lesson_plan].delete(:content_values) || []

      # Zip the keys and values into an array of hashes
      # The order is preserved as it comes from the form
      content = content_keys.zip(content_values).map { |type, details| { type => details } }

      # Permit lesson_plan attributes, include the content and chalkboard_enabled
      params.require(:lesson_plan).permit(:status, :chalkboard_enabled, :audio).tap do |whitelisted|
        whitelisted[:content] = content
      end
    end

    def find_linkable_resource!
      resource_scope_for_current_user.find(params[:resource_id])
    end

    def find_linked_resource!
      @lesson_plan.resources.merge(resource_scope_for_current_user).find(params[:resource_id])
    end

    def resource_scope_for_current_user
      return Resource.all if current_user.role_superuser?

      Resource.where(teacher_id: [ current_user.id, nil ])
    end

    def normalize_generation_steering
      preset = params[:preset].to_s.presence || "llm_decides"
      custom_guidance = params[:guidance].to_s.strip

      guidance = case preset
      when "llm_decides"
        nil
      when "speech_mobile"
        "Prefer a speech/mobile-style lesson. Keep it suitable for a narrow-screen or walk-and-talk format, and favor conversational delivery over chalkboard-heavy structure unless clearly warranted."
      when "offline_debrief"
        "Prefer an offline/debrief lesson structure. Include a clear away-from-device activity, concise completion criteria or work product expectations, and a brief return-and-debrief or return-and-confirm phase."
      when "other"
        return { error: "Enter lesson plan guidance when using the Other preset." } if custom_guidance.blank?

        custom_guidance
      else
        return { error: "Invalid lesson plan preset." }
      end

      { guidance: guidance }
    end

    def set_generation_submit_header(queued:)
      response.set_header("X-Lesson-Plan-Generation-Queued", queued ? "true" : "false")
    end

    def can_destroy_resource?(resource)
      current_user.role_superuser? || resource.teacher_id == current_user.id
    end

    def resource_proposal_enabled?
      AppSetting.openai_agent_enabled? && AppSetting.exa_enabled?
    end

    def authorize_generation_access!
      raise ActiveRecord::RecordNotFound if params[:course_id].to_i != @lesson.course_id
      return if current_user.role_superuser?
      raise ActiveRecord::RecordNotFound unless @lesson.course.teacher_id == current_user.id
    end
  end
end
