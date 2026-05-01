module TeacherAgent
  class SkillGenerator
    VERSION = "1.0.0".freeze

    def self.template_locals(base_url:, token_example: nil, skill_url: nil, user:)
      base_url = base_url.to_s.chomp("/")
      {
        version: VERSION,
        base_url: base_url,
        token_example: token_example.presence || "goa_live_your_token_here",
        skill_url: skill_url.presence || "#{base_url}/skill",
        teaching_principles: Prompt.get_prompt(category: "teaching_principles", user: user).to_s
      }
    end

    def initialize(base_url:, token_example: nil, skill_url: nil, user:)
      @base_url = base_url.to_s.chomp("/")
      @token_example = token_example.presence || "goa_live_your_token_here"
      @skill_url = skill_url.presence || "#{@base_url}/skill"
      @user = user
    end

    def call
      ApplicationController.render(
        template: "teacher_agent/skill",
        formats: [ :md ],
        layout: false,
        locals: self.class.template_locals(
          base_url: @base_url,
          token_example: @token_example,
          skill_url: @skill_url,
          user: @user
        )
      ).to_s
    end
  end
end
