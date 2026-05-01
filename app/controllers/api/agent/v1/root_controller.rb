module Api
  module Agent
    module V1
      class RootController < BaseController
        def status
          render json: success_payload(operations.status.merge(app_url: request.base_url))
        end

        def help
          command = params[:command].to_s.presence
          topic = params[:topic].to_s.presence
          if command && topic
            raise TeacherAgent::Operations::Error.new("Provide either command or topic, not both.", code: "invalid_help_request", http_status: :bad_request)
          end

          data = if command
            details = TeacherAgent::CommandCatalog.command(command)
            if details
              { command: command, details: details, related_help_topics: TeacherAgent::HelpTopicCatalog.command_topics(command) }
            else
              raise TeacherAgent::Operations::Error.new("Unknown command: #{command}", code: "unknown_command", http_status: :not_found)
            end
          elsif topic
            details = TeacherAgent::HelpTopicCatalog.topic(topic)
            if details
              { topic: topic, details: details }
            else
              raise TeacherAgent::Operations::Error.new("Unknown help topic: #{topic}", code: "unknown_help_topic", http_status: :not_found)
            end
          else
            {
              usage: "POST #{agent_base_url}/command with { \"command\": \"list_courses\", \"args\": {} }.",
              commands: TeacherAgent::CommandCatalog.commands,
              help_topics: TeacherAgent::HelpTopicCatalog.topics
            }
          end

          render json: success_payload(data)
        end

        def skill
          render plain: ApplicationController.render(
            template: "teacher_agent/skill",
            formats: [ :md ],
            layout: false,
            locals: skill_template_locals
          ),
                 content_type: "text/markdown"
        end

        private

        def skill_template_locals
          TeacherAgent::SkillGenerator.template_locals(
            base_url: agent_base_url,
            token_example: "goa_live_your_token_here",
            skill_url: "#{agent_base_url}/skill",
            user: current_agent_teacher
          )
        end
      end
    end
  end
end
