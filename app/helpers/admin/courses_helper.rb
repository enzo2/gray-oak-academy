module Admin
  module CoursesHelper
    DEFAULT_RESEARCH_CHOICE_LABELS = {
      "A" => "Keep current direction",
      "B" => "Adopt research recommendations",
      "C" => "Blend both approaches",
      "OTHER" => "Custom response"
    }.freeze

    def parse_outline_guidance_answer(raw_answer)
      parsed =
        case raw_answer
        when Hash
          raw_answer.deep_stringify_keys
        when String
          raw = raw_answer.to_s
          return { "choice" => "", "other_text" => "" } if raw.blank?

          JSON.parse(raw)
        else
          {}
        end
      choice = parsed["choice"].to_s.upcase
      return { "choice" => "", "other_text" => "" } unless %w[A B C OTHER].include?(choice)

      {
        "choice" => choice,
        "other_text" => parsed["other_text"].to_s
      }
    rescue JSON::ParserError
      { "choice" => "", "other_text" => "" }
    end

    def outline_question_choice_label(question_hash, key)
      normalized_key = key.to_s.upcase
      choices = question_hash.is_a?(Hash) && question_hash["choices"].is_a?(Hash) ? question_hash["choices"] : {}
      label = choices[normalized_key].to_s.strip
      label = choices[normalized_key.downcase].to_s.strip if label.blank?
      label.presence || DEFAULT_RESEARCH_CHOICE_LABELS[normalized_key]
    end

    def course_form_dom_id(course)
      course.persisted? ? dom_id(course, :form) : "course-form"
    end

    def outline_research_lock_message(course)
      return "" unless course.outline_research_in_progress?

      case course.outline_research_stage
      when "researching_outline"
        "Outline research is running. Course edits are temporarily locked."
      when "generating_guidance_questions"
        "Guidance is being prepared. Course edits are temporarily locked."
      when "applying_guidance_updates"
        "Research updates are being applied. Course edits are temporarily locked."
      else
        "Outline research is in progress. Course edits are temporarily locked."
      end
    end
  end
end
