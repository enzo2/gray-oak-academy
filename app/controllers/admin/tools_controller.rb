module Admin
  class ToolsController < AdminController
    before_action :require_admin
    before_action :set_tool, only: [ :show ]

    def index
      @tools = Tool.all
    end

    def show
      # The @tool instance variable is already set by the before_action
    end

    private

    def set_tool
      @tool = Tool.find(params[:id])
    end
  end
end
