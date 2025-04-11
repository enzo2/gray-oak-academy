module Admin
  class ToolsController < Admin::BaseController
    before_action :set_tool, only: [ :show, :edit, :update ]

    def index
      @tools = Tool.all
    end

    def show
    end

    def edit
    end

    def update
      if @tool.update(tool_params)
        redirect_to admin_tools_path
      else
        respond_to do |format|
          format.turbo_stream { render :update, status: :unprocessable_entity }
        end
      end
    end

    private

    def set_tool
      @tool = Tool.find(params[:id])
    end

    def tool_params
      # Parse the JSON string from the form into a hash
      params_hash = params.require(:tool).permit(:specifications)
      params_hash[:specifications] = JSON.parse(params_hash[:specifications])
      params_hash
    end
  end
end
