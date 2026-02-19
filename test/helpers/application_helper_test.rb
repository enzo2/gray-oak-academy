require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "reasoning_summary_lines extracts text lines from summary entries" do
    details = [
      {
        "type" => "reasoning",
        "summary" => [
          { "type" => "summary_text", "text" => "First summary line." },
          { "type" => "summary_text", "summary_text" => "Second summary line." }
        ]
      }
    ]

    assert_equal [ "First summary line.", "Second summary line." ], reasoning_summary_lines(details)
  end

  test "reasoning_summary_lines ignores empty and malformed entries" do
    details = [
      { "summary" => [ { "type" => "summary_text", "text" => "  " }, { "type" => "other" } ] },
      { "summary" => "Useful fallback line" },
      nil
    ]

    assert_equal [ "Useful fallback line" ], reasoning_summary_lines(details)
  end
end
