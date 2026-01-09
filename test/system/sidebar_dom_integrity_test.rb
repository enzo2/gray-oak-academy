require "application_system_test_case"

class SidebarDomIntegrityTest < ApplicationSystemTestCase
  def setup
    @student = users(:student)
    sign_in @student
    @conversation = conversations(:student_generic_conversation)
  end

  test "sidebar content is not duplicated (no duplicate DOM ids)" do
    visit conversation_path(@conversation)

    assert_selector 'nav[data-sidebar-singleton="true"]', visible: :all, wait: 5

    sidebar_link_id = ActionView::RecordIdentifier.dom_id(@conversation, :sidebar_link)

    assert_equal 1, page.evaluate_script("document.querySelectorAll('#conversation-list').length")
    assert_equal 1, page.evaluate_script("document.querySelectorAll('##{sidebar_link_id}').length")

    page.execute_script("window.dispatchEvent(new CustomEvent('sidebar:open-mobile'))")
    sleep 0.05

    assert_equal 1, page.evaluate_script("document.querySelectorAll('#conversation-list').length")
    assert_equal 1, page.evaluate_script("document.querySelectorAll('##{sidebar_link_id}').length")
  end
end
