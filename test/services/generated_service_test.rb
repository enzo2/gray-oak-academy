require "test_helper"

class ToolHandlerServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    ActiveJob::Base.queue_adapter = :test
    @conversation = conversations(:student_generic_conversation)
    @message = Message.create!(conversation: @conversation, role: :user, content: "Requesting tool")
  end

  test "execute Chalkboard_URL broadcasts and creates tool message" do
    # Ensure tool exists in DB so Tool.find_by can locate it
    chalk_spec = {
      "name" => "Chalkboard_URL",
      "description" => "Updates the chalkboard iframe",
      "parameters" => {
        "type" => "object",
        "properties" => {
          "url" => { "type" => "string", "description" => "URL to show" }
        },
        "required" => [ "url" ]
      }
    }
    Tool.create!(specifications: chalk_spec)

    service = ToolHandlerService.new(conversation: @conversation, message: @message)
    tool_calls = [ { id: "call-1", function: { name: "Chalkboard_URL", arguments: { url: "https://example.com" }.to_json } } ]

    # Stub Turbo broadcasts to avoid real ActionCable traffic
    Turbo::StreamsChannel.stub(:broadcast_update_to, true) do
      clear_enqueued_jobs
      service.execute_tool_calls(tool_calls)

      # A tool message should be created and GetLlmCompletionJob enqueued
      tool_messages = Message.where(role: "tool").order(created_at: :asc)
      assert tool_messages.any?, "Expected at least one tool message to be created"
      assert_enqueued_jobs 1, only: GetLlmCompletionJob
      assert_includes tool_messages.last.content, "Chalkboard URL was changed"
    end
  end

  test "execute Chalkboard_File raises tool message when resource missing" do
    chalk_file_spec = {
      "name" => "Chalkboard_File",
      "description" => "Displays a file on the chalkboard",
      "parameters" => {
        "type" => "object",
        "properties" => {
          "resource_id" => { "type" => "string", "description" => "ID of resource" }
        },
        "required" => [ "resource_id" ]
      }
    }
    Tool.create!(specifications: chalk_file_spec)

    service = ToolHandlerService.new(conversation: @conversation, message: @message)
    tool_call = { id: "call-2", name: "Chalkboard_File", arguments: { resource_id: "nonexistent" }.to_json }

    # Stub Turbo broadcast to avoid actual ActionCable usage
    Turbo::StreamsChannel.stub(:broadcast_update_to, true) do
      service.execute_tool_call(tool_call)
      tool_message = Message.where(role: "tool").order(created_at: :desc).first
      assert tool_message.present?, "Tool message should be created for errors"
      assert_includes tool_message.content, "Resource not found", "Expected error message for missing resource"
    end
  end

  test "execute Complete_Lesson creates StudentReport and broadcasts confirmation" do
    # Create tool record so it can be found and validated
    complete_spec = {
      "name" => "Complete_Lesson",
      "description" => "Marks the current lesson as completed and saves the LLM tutor's student report. This should be called at the end of a lesson. Be concise but thorough. Be specific, e.g. include quotations or evidence to support significant observations rather than drawing broad conclusions. Disregard prior reports and only consider progress during this lesson.",
      "parameters" => {
        "type" => "object",
        "properties" => {
          "summary" => {
            "type" => "string",
            "description" => "A brief summary of the student's performance and understanding during the lesson."
          },
          "strengths" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "List aspects (if any) where the student demonstrated adequate-to-strong understanding, which will require minimal to no review in subsequent lessons. May include knowledge or skills."
          },
          "areas_for_review" => {
            "type" => "array",
            "items" => { "type" => "string" },
            "description" => "List aspects (if any) where the student should receive additional clarification, review or practice in subsequent lessons."
          }
        },
        "required" => [ "summary", "strengths", "areas_for_review" ]
      }
    }
    Tool.create!(specifications: complete_spec)

    student = users(:student)
    lesson = lessons(:one) || Lesson.first
    lp = LessonProgress.find_or_create_by(student: student, lesson: lesson)
    conv = lp.find_or_create_conversation(student)

    msg = Message.create!(conversation: conv, role: :user, content: "Finish lesson")
    service = ToolHandlerService.new(conversation: conv, message: msg)

    args = {
      "summary" => "Student demonstrated good understanding of basic concepts and completed exercises successfully.",
      "strengths" => [ "Basic mechanics concepts", "Following instructions" ],
      "areas_for_review" => [ "Complex problem solving" ]
    }
    tool_call = { id: "call-3", name: "Complete_Lesson", arguments: args.to_json }

    # Stub broadcasting to avoid ActionCable during job creation
    Turbo::StreamsChannel.stub(:broadcast_append_later_to, true) do
      assert_difference("StudentReport.count", 1) do
        service.execute_tool_call(tool_call)
      end
    end

    report = StudentReport.order(created_at: :desc).first
    assert_equal lp.id, report.reportable_id
    assert_equal "lesson_progress", report.reportable_type.underscore, "Report should be associated with LessonProgress"
    tool_message = Message.where(role: "tool", tool_call_id: "call-3").first
    assert tool_message.present?
    assert_includes tool_message.content, "Confirmation: Lesson completed"
  end

  test "execute python_sandbox raises tool message when PythonCodeExecutorService returns error" do
    # Ensure tool exists in DB so Tool.find_by can locate it
    python_spec = {
      "name" => "python_sandbox",
      "description" => "Executes Python code in a secure sandbox",
      "parameters" => {
        "type" => "object",
        "properties" => {
          "code" => { "type" => "string", "description" => "Python code to execute" }
        },
        "required" => [ "code" ]
      }
    }
    Tool.create!(specifications: python_spec)

    service = ToolHandlerService.new(conversation: @conversation, message: @message)
    tool_call = { id: "call-4", name: "python_sandbox", arguments: { code: "raise Exception('test error')" }.to_json }

    PythonCodeExecutorService.stub(:execute, ->(_code) { { error: "Python execution failed" } }) do
      service.execute_tool_call(tool_call)
      tool_message = Message.where(role: "tool").order(created_at: :desc).first
      assert tool_message.present?, "Tool message should be created for errors"
      assert_includes tool_message.content, "Python execution failed", "Expected error message for Python execution failure"
    end
  end
end

class PythonCodeExecutorServiceTest < ActiveSupport::TestCase
  test "execute returns parsed JSON on success and error hash on failure" do
    code = "print(1+1)"

    # Successful path: create a response object that behaves like Net::HTTPSuccess
    net_obj = Object.new
    def net_obj.request(req)
      Object.new.tap do |o|
        def o.body; '{"final_expression":2,"success":true}'; end
        def o.is_a?(klass); klass == Net::HTTPSuccess; end
      end
    end

    orig_http_new = Net::HTTP.method(:new) rescue nil
    Net::HTTP.define_singleton_method(:new) { |host, port| net_obj }
    begin
      result = PythonCodeExecutorService.execute(code)
      assert result.is_a?(Hash)
      assert_equal true, result["success"]
    ensure
      Net::HTTP.define_singleton_method(:new, &orig_http_new.to_proc) if orig_http_new
    end

    # Simulate network error
    Net::HTTP.define_singleton_method(:new) { |host, port| raise "connection failed" }
    begin
      result = PythonCodeExecutorService.execute(code)
      assert result.is_a?(Hash)
      assert_includes result[:error] || result["error"], "connection failed"
    ensure
      Net::HTTP.define_singleton_method(:new, &orig_http_new.to_proc) if orig_http_new
    end
  end
end
