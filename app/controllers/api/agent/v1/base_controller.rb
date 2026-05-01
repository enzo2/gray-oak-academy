module Api
  module Agent
    module V1
      class BaseController < ActionController::API
        before_action :authenticate_agent_api_key!
        around_action :audit_agent_request

        rescue_from StandardError, with: :render_internal_error
        rescue_from TeacherAgent::Operations::Error, with: :render_operation_error
        rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid
        rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
        rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_parse_error

        private

        attr_reader :current_agent_key, :current_agent_teacher

        def authenticate_agent_api_key!
          token = request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
          key = AgentApiKey.authenticate(token)
          if key.nil? || !key.user.role_teacher?
            render json: error_payload("unauthorized", "Missing or invalid agent API bearer token."), status: :unauthorized
            return
          end

          @current_agent_key = key
          @current_agent_teacher = key.user
        end

        def audit_agent_request
          requested_at = Time.current
          yield
        rescue ActionDispatch::Http::Parameters::ParseError => e
          @agent_error_code = "invalid_json"
          @agent_error_message = e.message
          @agent_audit_status = 400
          raise
        rescue TeacherAgent::Operations::Error => e
          @agent_error_code = e.code
          @agent_error_message = e.message
          @agent_audit_status = Rack::Utils.status_code(e.http_status)
          raise
        rescue ActiveRecord::RecordInvalid => e
          @agent_error_code = "validation_failed"
          @agent_error_message = e.record.errors.full_messages.to_sentence
          @agent_audit_status = 422
          raise
        rescue ActiveRecord::RecordNotFound => e
          @agent_error_code = "not_found"
          @agent_error_message = e.message
          @agent_audit_status = 404
          raise
        rescue StandardError => e
          @agent_error_code = "internal_error"
          @agent_error_message = e.message
          @agent_audit_status = 500
          raise
        ensure
          record_agent_api_event(requested_at) if current_agent_key.present? && current_agent_teacher.present?
        end

        def record_agent_api_event(requested_at)
          AgentApiEvent.create!(
            user: current_agent_teacher,
            agent_api_key: current_agent_key,
            request_method: request.request_method,
            path: request.path,
            command: @agent_command.presence,
            status: @agent_audit_status || response.status,
            record_ids: @agent_record_ids || {},
            error_code: @agent_error_code,
            error_message: @agent_error_message,
            requested_at: requested_at || Time.current
          )
        rescue StandardError => e
          Rails.logger.warn("Agent API audit event failed: #{e.class}: #{e.message}")
        end

        def operations
          @operations ||= TeacherAgent::Operations.new(teacher: current_agent_teacher)
        end

        def success_payload(data, warnings: [])
          { ok: true, data: data, warnings: warnings }
        end

        def error_payload(code, message)
          { ok: false, error: { code: code, message: message } }
        end

        def render_operation_error(error)
          @agent_error_code = error.code
          @agent_error_message = error.message
          render json: error_payload(error.code, error.message), status: error.http_status
        end

        def render_record_invalid(error)
          @agent_error_code = "validation_failed"
          @agent_error_message = error.record.errors.full_messages.to_sentence
          render json: error_payload(@agent_error_code, @agent_error_message), status: :unprocessable_content
        end

        def render_not_found(error)
          @agent_error_code = "not_found"
          @agent_error_message = error.message
          render json: error_payload("not_found", "Record not found."), status: :not_found
        end

        def render_parse_error(error)
          @agent_error_code = "invalid_json"
          @agent_error_message = error.message
          render json: error_payload("invalid_json", "Request body must be valid JSON."), status: :bad_request
        end

        def render_internal_error(error)
          @agent_error_code = "internal_error"
          @agent_error_message = error.message
          Rails.logger.error("Agent API internal error: #{error.class}: #{error.message}")
          render json: error_payload("internal_error", "Command failed unexpectedly."), status: :internal_server_error
        end

        def agent_base_url
          "#{request.base_url}/api/agent/v1"
        end
      end
    end
  end
end
