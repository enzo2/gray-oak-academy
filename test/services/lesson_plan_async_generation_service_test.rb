require "test_helper"

class LessonPlanAsyncGenerationServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  def setup
    Rails.cache.clear
    @teacher = users(:admin)
    @lesson_plan = lesson_plans(:one)
    @lesson_plan.update!(generation_stage: "idle", generation_error: nil)
  end

  def teardown
    Rails.cache.clear
    travel_back
  end

  test "dedupes when generation is already in progress" do
    with_memory_cache do
      @lesson_plan.update!(generation_stage: "generating_content")
      service = LessonPlanAsyncGenerationService.new(
        lesson_plan: @lesson_plan,
        current_user: @teacher,
        source: "lesson_plan_button"
      )

      result = service.enqueue_generate_content(propose_resources: false)
      assert_equal false, result[:ok]
      assert_includes result[:message], "already in progress"
    end
  end

  test "cooldown blocks immediate retrigger after enqueue" do
    with_memory_cache do
      service = LessonPlanAsyncGenerationService.new(
        lesson_plan: @lesson_plan,
        current_user: @teacher,
        source: "lesson_plan_button"
      )

      assert_enqueued_jobs 1, only: GenerateLessonPlanPipelineJob do
        result = service.enqueue_generate_content(propose_resources: false)
        assert_equal true, result[:ok]
      end

      @lesson_plan.update!(generation_stage: "completed")
      assert_enqueued_jobs 0, only: GenerateLessonPlanPipelineJob do
        result = service.enqueue_generate_content(propose_resources: false)
        assert_equal false, result[:ok]
        assert_includes result[:message], "just queued"
      end
    end
  end

  test "cooldown expires and allows enqueue again" do
    with_memory_cache do
      service = LessonPlanAsyncGenerationService.new(
        lesson_plan: @lesson_plan,
        current_user: @teacher,
        source: "lesson_plan_button"
      )

      assert_enqueued_jobs 1, only: GenerateLessonPlanPipelineJob do
        result = service.enqueue_generate_content(propose_resources: false)
        assert_equal true, result[:ok]
      end

      @lesson_plan.update!(generation_stage: "completed")
      travel 31.seconds do
        assert_enqueued_jobs 1, only: GenerateLessonPlanPipelineJob do
          result = service.enqueue_generate_content(propose_resources: false)
          assert_equal true, result[:ok]
        end
      end
    end
  end

  test "propose resources forwards source and sets stage" do
    with_memory_cache do
      @lesson_plan.update!(generation_stage: "completed")
      service = LessonPlanAsyncGenerationService.new(
        lesson_plan: @lesson_plan,
        current_user: @teacher,
        source: "teacher_chat_tool"
      )

      captured_kwargs = nil
      AppSetting.stub(:openai_agent_enabled?, true) do
        AppSetting.stub(:exa_enabled?, true) do
          ProposeResourcesJob.stub(:perform_later, ->(*_args, **kwargs) { captured_kwargs = kwargs }) do
            result = service.enqueue_propose_resources
            assert_equal true, result[:ok]
            assert_equal "proposing_resources", result[:stage]
          end
        end
      end

      assert_equal "teacher_chat_tool", captured_kwargs[:source]
      assert_equal "proposing_resources", @lesson_plan.reload.generation_stage
    end
  end

  test "propose resources is not blocked by generate-content cooldown" do
    with_memory_cache do
      service = LessonPlanAsyncGenerationService.new(
        lesson_plan: @lesson_plan,
        current_user: @teacher,
        source: "lesson_plan_button"
      )

      AppSetting.stub(:openai_agent_enabled?, true) do
        AppSetting.stub(:exa_enabled?, true) do
          assert_enqueued_jobs 1, only: GenerateLessonPlanPipelineJob do
            result = service.enqueue_generate_content(propose_resources: false)
            assert_equal true, result[:ok]
          end

          @lesson_plan.update!(generation_stage: "completed")
          assert_enqueued_jobs 1, only: ProposeResourcesJob do
            result = service.enqueue_propose_resources
            assert_equal true, result[:ok]
            assert_equal "proposing_resources", result[:stage]
          end
        end
      end
    end
  end

  private

  def with_memory_cache
    cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stub(:cache, cache) { yield }
  end
end
