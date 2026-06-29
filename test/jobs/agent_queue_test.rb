require "test_helper"
require "erb"
require "yaml"

class AgentQueueTest < ActiveSupport::TestCase
  test "long-running agent jobs use the isolated agent queue" do
    assert_equal "agent", ProposeResourcesJob.new.queue_name
    assert_equal "agent", ResumeCourseOutlineResearchJob.new.queue_name
    assert_equal "agent", EnrichCourseOutlineJob.new.queue_name
    assert_equal "agent", GenerateLessonPlanPipelineJob.new.queue_name
    assert_equal "default", GetResponsesCompletionJob.new.queue_name
  end

  test "solid queue gives agent work a worker pool isolated from interactive jobs" do
    workers = production_queue_config.fetch("workers")
    interactive_worker = workers.find { |worker| worker["queues"] == [ "default", "mailers" ] }
    agent_worker = workers.find { |worker| worker["queues"] == "agent" }

    assert interactive_worker, "expected a worker dedicated to the default/mailers queues"
    assert agent_worker, "expected a worker dedicated to the agent queue"
    refute_same interactive_worker, agent_worker, "agent queue must not share a worker pool with interactive jobs"

    # These jobs are I/O-bound, so each pool runs several threads concurrently
    # rather than relying on extra processes.
    assert_operator agent_worker.fetch("threads").to_i, :>=, 1
    assert_operator interactive_worker.fetch("threads").to_i, :>=, 1
    assert_equal 1, agent_worker.fetch("processes").to_i
  end

  test "database pool covers the busiest solid queue worker so job threads are not connection-starved" do
    max_worker_threads = production_queue_config.fetch("workers").map { |worker| worker.fetch("threads").to_i }.max
    pool = database_config.dig("production", "primary", "max_connections").to_i

    assert_operator pool, :>=, max_worker_threads,
      "DB pool (#{pool}) must cover the busiest worker's #{max_worker_threads} threads, since each running job holds one connection"
  end

  test "development uses solid queue through the puma plugin" do
    development = database_config.fetch("development")
    puma_config = Rails.root.join("config/puma.rb").read

    assert development.key?("queue")
    assert_equal "db/queue_migrate", development.dig("queue", "migrations_paths")
    assert_includes Rails.root.join("config/environments/development.rb").read, "config.active_job.queue_adapter = :solid_queue"
    assert_includes puma_config, "plugin :solid_queue"
    assert_includes puma_config, "development production"
  end

  test "development uses solid_cable so cross-process job broadcasts reach the browser" do
    # Agent jobs run in forked Solid Queue processes, so the in-process `async`
    # cable adapter would only surface Turbo broadcasts after a manual refresh.
    development_cable = cable_config.fetch("development")
    development_db = database_config.fetch("development")

    assert_equal "solid_cable", development_cable["adapter"]
    assert_equal "cable", development_cable.dig("connects_to", "database", "writing")
    assert development_db.key?("cable"), "development needs a cable database for solid_cable"
    assert_equal "db/cable_migrate", development_db.dig("cable", "migrations_paths")
  end

  test "solid queue workers cover every app and framework queue" do
    missing = required_queue_names.reject { |queue| serviced_queue?(queue) }

    assert_empty missing, "Missing Solid Queue workers for queues: #{missing.join(', ')}"
  end

  private

  def required_queue_names
    (app_job_queue_names + framework_queue_names).compact.uniq.sort
  end

  def app_job_queue_names
    app_job_classes.map { |job_class| job_class.new.queue_name.to_s }
  end

  def app_job_classes
    Dir[Rails.root.join("app/jobs/**/*_job.rb")].filter_map do |path|
      relative = Pathname.new(path).relative_path_from(Rails.root.join("app/jobs")).to_s.delete_suffix(".rb")
      next if relative == "application_job"

      relative.camelize.safe_constantize
    end
  end

  def framework_queue_names
    active_storage_queues = %w[
      ActiveStorage::AnalyzeJob
      ActiveStorage::PurgeJob
      ActiveStorage::TransformJob
      ActiveStorage::CreateVariantsJob
      ActiveStorage::MirrorJob
      ActiveStorage::SyncMetadataJob
    ].filter_map do |class_name|
      constantize_framework_job(class_name)&.new&.queue_name&.to_s
    end

    mailer_queue = ApplicationMailer.deliver_later_queue_name || ActionMailer::Base.deliver_later_queue_name || :mailers
    [ mailer_queue.to_s ] + active_storage_queues
  end

  def constantize_framework_job(class_name)
    class_name.split("::").reduce(Object) do |namespace, constant_name|
      return nil unless namespace.const_defined?(constant_name, false)

      namespace.const_get(constant_name, false)
    end
  rescue NameError
    nil
  end

  def serviced_queue?(queue)
    serviced_queue_names.include?("*") || serviced_queue_names.include?(queue.to_s)
  end

  def serviced_queue_names
    @serviced_queue_names ||= production_queue_config.fetch("workers").flat_map do |worker|
      Array(worker.fetch("queues"))
    end.map(&:to_s).uniq
  end

  def production_queue_config
    @production_queue_config ||= YAML.safe_load(
      ERB.new(Rails.root.join("config/queue.yml").read).result,
      aliases: true
    ).fetch("production")
  end

  def database_config
    @database_config ||= YAML.safe_load(
      ERB.new(Rails.root.join("config/database.yml").read).result,
      aliases: true
    )
  end

  def cable_config
    @cable_config ||= YAML.safe_load(
      ERB.new(Rails.root.join("config/cable.yml").read).result,
      aliases: true
    )
  end
end
