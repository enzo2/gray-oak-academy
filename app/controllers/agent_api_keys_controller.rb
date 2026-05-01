class AgentApiKeysController < ApplicationController
  before_action :require_admin

  def create
    key, token = AgentApiKey.create_with_token!(
      user: current_user,
      name: params.dig(:agent_api_key, :name)
    )
    flash[:success] = "Agent API key created. Copy it now; it will not be shown again."
    flash[:agent_api_token] = token
    flash[:agent_api_key_prefix] = key.visible_prefix
    redirect_to edit_user_registration_path(active_tab: :agent_access)
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = e.record.errors.full_messages.to_sentence
    redirect_to edit_user_registration_path(active_tab: :agent_access), status: :see_other
  end

  def destroy
    current_user.agent_api_keys.find(params[:id]).revoke!
    flash[:success] = "Agent API key revoked."
    redirect_to edit_user_registration_path(active_tab: :agent_access), status: :see_other
  end

  def skill
    render template: "teacher_agent/skill",
           formats: [ :md ],
           layout: false,
           content_type: "text/markdown",
           locals: skill_template_locals(token_example: "goa_live_your_token_here")
  end

  private

  def agent_base_url
    "#{request.base_url}/api/agent/v1"
  end

  def skill_template_locals(token_example: nil)
    TeacherAgent::SkillGenerator.template_locals(
      base_url: agent_base_url,
      token_example: token_example.presence || "goa_live_your_token_here",
      skill_url: "#{agent_base_url}/skill",
      user: current_user
    )
  end
end
