module Api
  module Agent
    module V1
      class CommandsController < BaseController
        def create
          parsed_params = params
          command = parsed_params[:command].to_s
          @agent_command = command
          args = command_args(parsed_params)

          data = TeacherAgent::CommandCatalog.execute(command, operations, args)
          @agent_record_ids = operations.touched_records
          render json: success_payload(data)
        end

        private

        def command_args(parsed_params)
          raw_args = parsed_params[:args]
          case raw_args
          when ActionController::Parameters
            raw_args.to_unsafe_h
          when Hash
            raw_args
          when nil
            {}
          else
            raise TeacherAgent::Operations::Error.new("args must be a JSON object.", code: "invalid_args", http_status: :bad_request)
          end
        end
      end
    end
  end
end
