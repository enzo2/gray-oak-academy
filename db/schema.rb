# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.2].define(version: 2026_06_18_000100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "audio_setting", ["disabled", "enabled", "audio-only"]
  create_enum "content_type", ["image/png", "image/jpeg", "image/webp"]
  create_enum "course_kind", ["full_course", "quick_lesson"]
  create_enum "course_status", ["active", "archived"]
  create_enum "lesson_plan_status", ["draft", "published", "archived"]
  create_enum "observation_status", ["pending", "approved", "rejected", "archived"]
  create_enum "prompt_category", ["other", "generate_course_outline", "generate_lessons", "generate_lesson_plan", "suggest_resources", "lesson_tutor_session", "open_ended_student_chat", "auto_name_conversation", "student_progress_tutor_session", "generate_student_lesson_report", "generate_student_course_report", "generate_student_assessment_report", "generate_student_profile", "tool_usage", "delegate_to_frontier_llm", "memories_semantic_merge", "generative_guidelines", "teacher_assistant", "teaching_principles", "base_system_prompt", "generate_observations", "research_course_outline", "analyze_course_outline_research", "apply_course_outline_research"]
  create_enum "report_author_type", ["ai_generated", "teacher_written"]
  create_enum "role_name", ["system", "user", "assistant", "tool"]
  create_enum "student_report_status", ["in_progress", "completed"]
  create_enum "user_role", ["student", "admin", "superuser"]

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_api_events", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "agent_api_key_id", null: false
    t.string "request_method", null: false
    t.string "path", null: false
    t.string "command"
    t.integer "status"
    t.jsonb "record_ids", default: {}, null: false
    t.string "error_code"
    t.text "error_message"
    t.datetime "requested_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_api_key_id"], name: "index_agent_api_events_on_agent_api_key_id"
    t.index ["command"], name: "index_agent_api_events_on_command"
    t.index ["requested_at"], name: "index_agent_api_events_on_requested_at"
    t.index ["status"], name: "index_agent_api_events_on_status"
    t.index ["user_id"], name: "index_agent_api_events_on_user_id"
  end

  create_table "agent_api_keys", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "token_digest", null: false
    t.string "visible_prefix", null: false
    t.datetime "last_used_at"
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["revoked_at"], name: "index_agent_api_keys_on_revoked_at"
    t.index ["token_digest"], name: "index_agent_api_keys_on_token_digest", unique: true
    t.index ["user_id"], name: "index_agent_api_keys_on_user_id"
    t.index ["visible_prefix"], name: "index_agent_api_keys_on_visible_prefix"
  end

  create_table "agent_runs", force: :cascade do |t|
    t.string "run_id", null: false
    t.string "response_id"
    t.string "status"
    t.string "teacher_name"
    t.bigint "teacher_id"
    t.string "model"
    t.string "provider_base_uri"
    t.string "source"
    t.string "task_preview"
    t.text "task_prompt"
    t.string "metadata_version"
    t.string "phase"
    t.datetime "submitted_at"
    t.datetime "finished_at"
    t.decimal "duration_seconds", precision: 10, scale: 1
    t.integer "assistant_turns"
    t.integer "tool_call_count"
    t.integer "tool_turn_count"
    t.integer "reasoning_item_count"
    t.integer "output_item_count"
    t.jsonb "tool_calls", default: [], null: false
    t.jsonb "events", default: [], null: false
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["response_id"], name: "index_agent_runs_on_response_id"
    t.index ["run_id"], name: "index_agent_runs_on_run_id", unique: true
    t.index ["submitted_at"], name: "index_agent_runs_on_submitted_at"
  end

  create_table "app_settings", force: :cascade do |t|
    t.jsonb "settings", default: {}, null: false
    t.boolean "singleton", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "log", default: {}, null: false
    t.index ["singleton"], name: "index_app_settings_on_singleton", unique: true
  end

  create_table "applets", force: :cascade do |t|
    t.string "title"
    t.text "code"
    t.boolean "archived"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "resource_id"
    t.index ["resource_id"], name: "index_applets_on_resource_id"
    t.index ["user_id"], name: "index_applets_on_user_id"
  end

  create_table "audios", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.string "content_type", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_audios_on_message_id"
  end

  create_table "completions", force: :cascade do |t|
    t.string "model"
    t.string "model_provider"
    t.string "api_provider"
    t.integer "prompt_tokens"
    t.integer "prompt_audio_tokens"
    t.integer "cached_tokens"
    t.integer "reasoning_tokens"
    t.integer "completion_tokens"
    t.integer "completion_audio_tokens"
    t.integer "total_tokens"
    t.decimal "total_cost", precision: 6, scale: 4
    t.decimal "cache_discount", precision: 6, scale: 4
    t.integer "latency"
    t.integer "generation_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "llm_id", null: false
    t.bigint "conversation_id"
    t.bigint "user_id"
    t.index ["api_provider"], name: "index_completions_on_api_provider"
    t.index ["conversation_id"], name: "index_completions_on_conversation_id"
    t.index ["llm_id"], name: "index_completions_on_llm_id"
    t.index ["model"], name: "index_completions_on_model"
    t.index ["model_provider"], name: "index_completions_on_model_provider"
    t.index ["user_id"], name: "index_completions_on_user_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "lesson_progress_id"
    t.string "title", null: false
    t.string "task_system_prompt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "responses_previous_id"
    t.string "responses_provider"
    t.string "responses_model"
    t.index ["lesson_progress_id"], name: "index_conversations_on_lesson_progress_id"
    t.index ["user_id"], name: "index_conversations_on_user_id"
  end

  create_table "courses", force: :cascade do |t|
    t.string "title"
    t.text "summary"
    t.jsonb "outline", default: []
    t.string "grade_level"
    t.bigint "teacher_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.enum "status", default: "active", null: false, enum_type: "course_status"
    t.string "outline_research_stage", default: "idle", null: false
    t.text "outline_research_error"
    t.jsonb "outline_research", default: {}, null: false
    t.text "outline_guidance_report_md"
    t.jsonb "outline_guidance_questions", default: [], null: false
    t.jsonb "outline_guidance_answers", default: {}, null: false
    t.string "outline_research_run_id"
    t.string "outline_research_response_id"
    t.jsonb "course_prior_state", default: {}, null: false
    t.enum "kind", default: "full_course", null: false, enum_type: "course_kind"
    t.index ["kind"], name: "index_courses_on_kind"
    t.index ["outline_research_stage"], name: "index_courses_on_outline_research_stage"
    t.index ["teacher_id"], name: "index_courses_on_teacher_id"
  end

  create_table "enrollments", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "course_id", null: false
    t.boolean "completed"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["course_id"], name: "index_enrollments_on_course_id"
    t.index ["student_id", "course_id"], name: "index_enrollments_on_student_id_and_course_id", unique: true
    t.index ["student_id"], name: "index_enrollments_on_student_id"
  end

  create_table "images", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.string "uri"
    t.enum "content_type", null: false, enum_type: "content_type"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_images_on_message_id"
  end

  create_table "lesson_plans", force: :cascade do |t|
    t.jsonb "content"
    t.enum "status", default: "draft", null: false, enum_type: "lesson_plan_status"
    t.bigint "lesson_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "chalkboard_enabled", default: true, null: false
    t.enum "audio", default: "enabled", null: false, enum_type: "audio_setting"
    t.jsonb "suggested_resources", default: []
    t.string "generation_stage", default: "idle", null: false
    t.text "generation_error"
    t.jsonb "generation_metadata", default: {}, null: false
    t.index ["generation_stage"], name: "index_lesson_plans_on_generation_stage"
    t.index ["lesson_id"], name: "index_lesson_plans_on_lesson_id", unique: true
  end

  create_table "lesson_plans_resources", id: false, force: :cascade do |t|
    t.bigint "lesson_plan_id", null: false
    t.bigint "resource_id", null: false
    t.index ["lesson_plan_id", "resource_id"], name: "index_lesson_plans_resources_on_lesson_plan_id_and_resource_id", unique: true
  end

  create_table "lesson_progresses", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "lesson_id", null: false
    t.jsonb "chat_history"
    t.jsonb "progress_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "completed_at"
    t.integer "duration"
    t.index ["lesson_id"], name: "index_lesson_progresses_on_lesson_id"
    t.index ["student_id", "lesson_id"], name: "index_lesson_progresses_on_student_id_and_lesson_id", unique: true
    t.index ["student_id"], name: "index_lesson_progresses_on_student_id"
  end

  create_table "lessons", force: :cascade do |t|
    t.string "title"
    t.text "goals"
    t.integer "approx_duration_min"
    t.bigint "course_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "position"
    t.index ["course_id"], name: "index_lessons_on_course_id"
  end

  create_table "llms", force: :cascade do |t|
    t.string "model", null: false
    t.string "model_provider"
    t.string "api_provider", null: false
    t.integer "context_length"
    t.boolean "supports_tool_use"
    t.boolean "supports_structured_outputs"
    t.boolean "supports_image_input"
    t.boolean "supports_image_output"
    t.boolean "supports_audio_input"
    t.boolean "supports_audio_output"
    t.boolean "supports_streaming_audio"
    t.jsonb "supported_parameters"
    t.datetime "metadata_fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "archived_at"
    t.index ["archived_at"], name: "index_llms_on_archived_at"
    t.index ["model", "api_provider"], name: "index_llms_on_model_and_api_provider", unique: true
  end

  create_table "memories", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "author_id"
    t.bigint "student_report_id"
    t.text "body", null: false
    t.boolean "hidden_from_student", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.vector "embedding"
    t.index ["author_id"], name: "index_memories_on_author_id"
    t.index ["student_id"], name: "index_memories_on_student_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.enum "role", null: false, enum_type: "role_name"
    t.string "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "tool_calls"
    t.string "tool_call_id"
    t.jsonb "reasoning_details"
    t.jsonb "metadata"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.check_constraint "content IS NOT NULL OR tool_calls IS NOT NULL AND jsonb_array_length(tool_calls) > 0", name: "messages_content_or_tool_calls_present"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "recipient_id", null: false
    t.string "event_type"
    t.jsonb "params"
    t.datetime "read_at"
    t.string "link"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recipient_id"], name: "index_notifications_on_recipient_id"
  end

  create_table "observations", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "author_id"
    t.string "source_type"
    t.bigint "source_id"
    t.enum "status", default: "pending", null: false, enum_type: "observation_status"
    t.text "content", null: false
    t.vector "embedding"
    t.datetime "last_validated_at"
    t.decimal "relevance_weight", precision: 3, scale: 2, default: "1.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_observations_on_author_id"
    t.index ["source_type", "source_id"], name: "index_observations_on_source"
    t.index ["student_id"], name: "index_observations_on_student_id"
  end

  create_table "prompts", force: :cascade do |t|
    t.string "title"
    t.enum "category", default: "other", null: false, enum_type: "prompt_category"
    t.text "prompt"
    t.bigint "teacher_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["teacher_id"], name: "index_prompts_on_teacher_id"
  end

  create_table "resources", force: :cascade do |t|
    t.string "category"
    t.text "description"
    t.string "uri"
    t.bigint "teacher_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "include_by_default"
    t.string "tags", default: [], null: false, array: true
    t.boolean "approved"
    t.text "content"
    t.index ["approved"], name: "index_resources_on_approved"
    t.index ["category"], name: "index_resources_on_category"
    t.index ["tags"], name: "index_resources_on_tags", using: :gin
    t.index ["teacher_id"], name: "index_resources_on_teacher_id"
  end

  create_table "settings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_settings_on_user_id", unique: true
  end

  create_table "student_feedbacks", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "lesson_progress_id"
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lesson_progress_id"], name: "index_student_feedbacks_on_lesson_progress_id"
    t.index ["student_id"], name: "index_student_feedbacks_on_student_id"
  end

  create_table "student_reports", force: :cascade do |t|
    t.string "reportable_type"
    t.bigint "reportable_id"
    t.bigint "student_id", null: false
    t.bigint "teacher_id"
    t.enum "author_type", null: false, enum_type: "report_author_type"
    t.enum "status", null: false, enum_type: "student_report_status"
    t.jsonb "progress_data"
    t.text "report"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reportable_type", "reportable_id"], name: "index_student_reports_on_reportable"
    t.index ["student_id"], name: "index_student_reports_on_student_id"
    t.index ["teacher_id"], name: "index_student_reports_on_teacher_id"
  end

  create_table "supported_apis", force: :cascade do |t|
    t.string "api_base_uri", null: false
    t.text "api_access_token"
    t.boolean "enabled", default: true, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_base_uri"], name: "index_supported_apis_on_api_base_uri", unique: true
  end

  create_table "tools", force: :cascade do |t|
    t.jsonb "specifications"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.virtual "name", type: :string, as: "(specifications ->> 'name'::text)", stored: true
    t.virtual "description", type: :string, as: "(specifications ->> 'description'::text)", stored: true
    t.enum "access", default: "student", null: false, enum_type: "user_role"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.enum "role", default: "student", null: false, enum_type: "user_role"
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "teacher_id"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["teacher_id"], name: "index_users_on_teacher_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_api_events", "agent_api_keys"
  add_foreign_key "agent_api_events", "users"
  add_foreign_key "agent_api_keys", "users"
  add_foreign_key "applets", "resources"
  add_foreign_key "applets", "users"
  add_foreign_key "audios", "messages"
  add_foreign_key "completions", "conversations", on_delete: :nullify
  add_foreign_key "completions", "llms"
  add_foreign_key "completions", "users", on_delete: :nullify
  add_foreign_key "conversations", "lesson_progresses"
  add_foreign_key "conversations", "users"
  add_foreign_key "courses", "users", column: "teacher_id"
  add_foreign_key "enrollments", "courses"
  add_foreign_key "enrollments", "users", column: "student_id"
  add_foreign_key "images", "messages"
  add_foreign_key "lesson_plans", "lessons"
  add_foreign_key "lesson_progresses", "lessons"
  add_foreign_key "lesson_progresses", "users", column: "student_id"
  add_foreign_key "lessons", "courses"
  add_foreign_key "memories", "student_reports"
  add_foreign_key "memories", "users", column: "author_id"
  add_foreign_key "memories", "users", column: "student_id"
  add_foreign_key "messages", "conversations"
  add_foreign_key "notifications", "users", column: "recipient_id"
  add_foreign_key "observations", "users", column: "author_id"
  add_foreign_key "observations", "users", column: "student_id"
  add_foreign_key "prompts", "users", column: "teacher_id"
  add_foreign_key "resources", "users", column: "teacher_id"
  add_foreign_key "settings", "users"
  add_foreign_key "student_feedbacks", "lesson_progresses"
  add_foreign_key "student_feedbacks", "users", column: "student_id"
  add_foreign_key "student_reports", "users", column: "student_id"
  add_foreign_key "student_reports", "users", column: "teacher_id"
  add_foreign_key "users", "users", column: "teacher_id"
end
