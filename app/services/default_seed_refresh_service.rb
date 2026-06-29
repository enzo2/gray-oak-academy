class DefaultSeedRefreshService
  Result = Data.define(:default_prompts_deleted, :tools_deleted)

  def self.call(seed_loader: -> { Rails.application.load_seed }, output: $stdout)
    new(seed_loader:, output:).call
  end

  def initialize(seed_loader:, output:)
    @seed_loader = seed_loader
    @output = output
  end

  def call
    result = nil
    ActiveRecord::Base.transaction do
      result = delete_seeded_defaults
      seed_loader.call
    end

    output.puts "Deleted #{result.default_prompts_deleted} default prompt(s) and #{result.tools_deleted} tool(s)."
    output.puts "Reloaded defaults from db/seeds.rb."

    result
  end

  private

  attr_reader :seed_loader, :output

  def delete_seeded_defaults
    Result.new(
      default_prompts_deleted: Prompt.where(teacher_id: nil).delete_all,
      tools_deleted: Tool.delete_all
    )
  end
end
