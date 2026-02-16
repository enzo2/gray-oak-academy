class CourseOutlineResearchStubService
  ENV_KEY = "STUB_COURSE_OUTLINE_RESEARCH".freeze

  class << self
    def enabled?
      configured = ENV[ENV_KEY]
      return false if configured.blank?

      ActiveModel::Type::Boolean.new.cast(configured)
    end

    def research_payload(course:)
      {
        "source_anchors" => source_anchors(course: course),
        "coverage_gaps" => [
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
          "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
        ],
        "factual_notes" => [
          "Ut enim ad minim veniam, quis nostrud exercitation ullamco.",
          "Duis aute irure dolor in reprehenderit in voluptate velit esse."
        ],
        "alternative_approaches" => [
          "Cillum dolore eu fugiat nulla pariatur.",
          "Excepteur sint occaecat cupidatat non proident."
        ],
        "research_id" => "stub_research_#{course.id}",
        "generated_at" => Time.current.iso8601,
        "exa_research" => {
          "research_id" => "stub_research_#{course.id}",
          "status" => "completed",
          "poll_count" => 0,
          "started_at" => Time.current.iso8601,
          "last_checked_at" => Time.current.iso8601,
          "provider_updated_at" => Time.current.iso8601,
          "message" => "Development stub response."
        }
      }
    end

    def guidance_payload(course:)
      {
        "report_markdown" => <<~MD.strip,
          ## Stubbed Guidance Report
          Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.

          ### Suggested Emphasis
          - Ut enim ad minim veniam.
          - Quis nostrud exercitation ullamco laboris.
          - Duis aute irure dolor in reprehenderit.
        MD
        "research_questions" => [
          question(
            id: "q1",
            text: "Should the opening unit be streamlined?",
            choices: [ "Keep current structure", "Shorten with focused essentials", "Blend both approaches", "Custom direction" ]
          ),
          question(
            id: "q2",
            text: "How much project-based work should be included?",
            choices: [ "Minimal projects", "Moderate projects", "Project-heavy", "Custom direction" ]
          ),
          question(
            id: "q3",
            text: "Should source analysis be introduced earlier?",
            choices: [ "Keep current timing", "Move earlier", "Distribute across units", "Custom direction" ]
          ),
          question(
            id: "q4",
            text: "How should pacing change for the middle section?",
            choices: [ "Keep pacing", "Slow down", "Speed up", "Custom direction" ]
          ),
          question(
            id: "q5",
            text: "Should a cumulative checkpoint be added?",
            choices: [ "No checkpoint", "One checkpoint", "Multiple checkpoints", "Custom direction" ]
          )
        ]
      }
    end

    def prefilled_guidance_answers(questions)
      cycle = [ "A", "B", "C", "OTHER", "B" ]
      answers = Array(questions).each_with_index.each_with_object({}) do |(question, idx), memo|
        question_id = question["id"].to_s
        next if question_id.blank?

        choice = cycle[idx % cycle.length]
        memo[question_id] =
          if choice == "OTHER"
            { "choice" => "OTHER", "other_text" => "Lorem ipsum dolor sit amet." }
          else
            { "choice" => choice }
          end
      end
      answers[Course::OUTLINE_GUIDANCE_ADDITIONAL_COMMENTS_KEY] = "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
      answers
    end

    def apply_update_payload(course:)
      {
        summary: [
          course.summary.to_s,
          "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
        ].reject(&:blank?).join("\n\n"),
        outline: [
          { topic: "Lorem Ipsum Foundations", description: "Lorem ipsum dolor sit amet, consectetur adipiscing elit." },
          { topic: "Dolor Analysis", description: "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua." },
          { topic: "Applied Synthesis", description: "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip." }
        ],
        outline_guidance_report_md: <<~MD.strip,
          ## Stubbed Applied Guidance
          Lorem ipsum dolor sit amet, consectetur adipiscing elit.

          ### Applied Changes
          - Sed do eiusmod tempor incididunt ut labore.
          - Ut enim ad minim veniam.
          - Duis aute irure dolor in reprehenderit.
        MD
        outline_research: apply_outline_research(course: course)
      }
    end

    def apply_summary_markdown
      <<~MD.strip
        Applied stubbed course updates.

        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.
      MD
    end

    private

    def source_anchors(course:)
      [
        {
          "id" => "anchor_1",
          "title" => "#{course.title} reference one",
          "url" => "https://example.com/stub-source-1",
          "excerpt" => "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
          "highlights" => [
            "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
            "Ut enim ad minim veniam."
          ],
          "notes" => "Duis aute irure dolor in reprehenderit."
        },
        {
          "id" => "anchor_2",
          "title" => "#{course.title} reference two",
          "url" => "https://example.com/stub-source-2",
          "excerpt" => "Quis nostrud exercitation ullamco laboris nisi ut aliquip.",
          "highlights" => [
            "Excepteur sint occaecat cupidatat non proident."
          ],
          "notes" => "Sunt in culpa qui officia deserunt mollit anim id est laborum."
        }
      ]
    end

    def question(id:, text:, choices:)
      {
        "id" => id.to_s,
        "question" => text.to_s,
        "choices" => {
          "A" => choices[0].to_s,
          "B" => choices[1].to_s,
          "C" => choices[2].to_s,
          "OTHER" => choices[3].to_s
        }
      }
    end

    def apply_outline_research(course:)
      payload = course.outline_research_hash.deep_dup
      payload["coverage_gaps"] = [
        "Lorem ipsum dolor sit amet.",
        "Consectetur adipiscing elit."
      ]
      payload["factual_notes"] = [
        "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
      ]
      payload["alternative_approaches"] = [
        "Ut enim ad minim veniam."
      ]
      payload
    end
  end
end
