module Admin
  class LessonPlansController < ApplicationController
    before_action :require_admin
    before_action :set_lesson
    before_action :set_lesson_plan, only: [ :edit, :update, :link_resource, :unlink_resource, :add_resource ]

    def generate
      # Auto-generate lesson plan content using LLM
    end

    def edit
      # Render the edit form for the lesson plan
      respond_to do |format|
        format.turbo_stream
      end
    end

    def update
      if @lesson_plan.update(lesson_plan_params)
        respond_to do |format|
          format.turbo_stream
        end
      else
        respond_to do |format|
          format.turbo_stream { render :update, status: :unprocessable_entity }
        end
      end
    end

    def link_resource
      @resource = Resource.find_or_create_by(id: params[:resource_id]) do |resource|
        resource.attributes = resource_params
      end

      @lesson_plan.resources << @resource unless @lesson_plan.resources.include?(@resource)

      respond_to do |format|
        format.turbo_stream
      end
    end

    def unlink_resource
      @resource = Resource.find(params[:resource_id])
      @lesson_plan.resources.delete(@resource)

      respond_to do |format|
        format.turbo_stream
      end
    end

    def add_resource
      @resource = Resource.new(resource_params)

      if @resource.save
        @lesson_plan.resources << @resource
        respond_to do |format|
          format.turbo_stream
        end
      else
        respond_to do |format|
          format.turbo_stream { render :add_resource_error, status: :unprocessable_entity }
        end
      end
    end

    private

    def set_lesson
      @lesson = Lesson.find(params[:lesson_id])
    end

    def set_lesson_plan
      @lesson_plan = @lesson.lesson_plan || @lesson.build_lesson_plan(teacher: current_user)
    end

    def lesson_plan_params
      # Extract `content_keys` and `content_values` from params, default empty arrays if not present
      content_keys = params[:lesson_plan].delete(:content_keys) || []
      content_values = params[:lesson_plan].delete(:content_values) || []

      # Zip the keys and values into a hash and store it as `content`
      content = content_keys.zip(content_values).to_h

      # Permit lesson_plan attributes, include the content hash, and handle nested resources
      params.require(:lesson_plan).permit(
        :status# ,
        # resource_ids: [],
        # resources_attributes: [ :id, :category, :description, :uri, :_destroy ]
      ).merge(content: content)
    end

    def resource_params
      params.require(:resource).permit(:category, :description, :uri)
    end
  end
end
