require "test_helper"

module Admin
  class PromptsControllerTest < ActionDispatch::IntegrationTest
    test "regular admin destroying default prompt redirects once with authorization warning" do
      sign_in users(:admin)

      delete admin_prompt_url(prompts(:base_system_prompt))

      assert_redirected_to admin_prompts_url
      assert_equal "You are not authorized to edit this prompt.", flash[:warning]
    end

    test "superuser cannot destroy default prompt" do
      sign_in users(:super_user)
      prompt = prompts(:base_system_prompt)

      assert_no_difference "Prompt.count" do
        delete admin_prompt_url(prompt)
      end

      assert_redirected_to admin_prompts_url
      assert_equal "You cannot delete the default prompts.", flash[:warning]
      assert Prompt.exists?(prompt.id)
    end
  end
end
