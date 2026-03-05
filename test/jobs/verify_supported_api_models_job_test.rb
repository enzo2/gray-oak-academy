require "test_helper"

class VerifySupportedApiModelsJobTest < ActiveJob::TestCase
  test "verifies each model for superuser with supported api token" do
    admin = users(:admin)
    admin.update_column(:role, "superuser")

    supported_api = SupportedApi.create!(
      api_base_uri: "https://api.verify.test/",
      api_access_token: "tok123",
      enabled: true
    )

    called_models = []
    flash_calls = []
    OpenaiApiService.stub(:new, ->(**kwargs) {
      called_models << kwargs[:model]
      Object.new.tap do |service|
        service.define_singleton_method(:complete) { |_messages| true }
      end
    }) do
      Turbo::StreamsChannel.stub(:broadcast_update_to, ->(*args, **kwargs) { flash_calls << { args: args, kwargs: kwargs } }) do
        models = [ "m1", "m2" ]
        VerifySupportedApiModelsJob.perform_now(
          supported_api_id: supported_api.id,
          models: models,
          enqueued_by_user_id: admin.id
        )
        assert_equal models.sort, called_models.sort
      end
    end

    assert_empty flash_calls
  end

  test "broadcasts an error flash when model verification fails" do
    admin = users(:admin)
    admin.update_column(:role, "superuser")

    supported_api = SupportedApi.create!(
      api_base_uri: "https://api.verify.test/",
      api_access_token: "tok123",
      enabled: true
    )

    flash_calls = []
    OpenaiApiService.stub(:new, ->(**_kwargs) {
      Object.new.tap do |service|
        service.define_singleton_method(:complete) { |_messages| raise StandardError, "verification boom" }
      end
    }) do
      Turbo::StreamsChannel.stub(:broadcast_update_to, ->(*args, **kwargs) { flash_calls << { args: args, kwargs: kwargs } }) do
        VerifySupportedApiModelsJob.perform_now(
          supported_api_id: supported_api.id,
          models: [ "m1" ],
          enqueued_by_user_id: admin.id
        )
      end
    end

    assert_equal 1, flash_calls.size
    call = flash_calls.first
    assert_equal [ "teacher_#{admin.id}-dashboard" ], call[:args]
    assert_equal "flash_bar", call[:kwargs][:target]
    assert_equal "shared/flash", call[:kwargs][:partial]
    assert_includes call[:kwargs].dig(:locals, :flash, :error), "m1"
  end
end
