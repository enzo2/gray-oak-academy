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
    OpenaiApiService.stub(:new, ->(**kwargs) {
      called_models << kwargs[:model]
      Object.new.tap do |service|
        service.define_singleton_method(:complete) { |_messages| true }
      end
    }) do
      models = [ "m1", "m2" ]
      VerifySupportedApiModelsJob.perform_now(
        supported_api_id: supported_api.id,
        models: models,
        enqueued_by_user_id: admin.id
      )
      assert_equal models.sort, called_models.sort
    end
  end
end
