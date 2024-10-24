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

ActiveRecord::Schema[7.2].define(version: 2024_10_22_022016) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "lesson_plan_status", ["draft", "published", "archived"]
  create_enum "prompt_category", ["other", "generate_course_outline", "generate_lessons", "generate_lesson_plan", "suggest_resources", "lesson_tutor_session", "open_ended_student_chat", "student_progress_tutor_session", "generate_student_lesson_report", "generate_student_assessment_report", "generate_student_profile", "tool_usage", "teacher_assistant", "teaching_principles", "base_system_prompt"]
  create_enum "report_author_type", ["ai_generated", "teacher_written"]
  create_enum "role_name", ["system", "user", "assistant"]
  create_enum "student_report_status", ["in_progress", "completed"]
  create_enum "user_role", ["student", "admin"]

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

  create_table "conversations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "lesson_progress_id"
    t.string "title", null: false
    t.string "task_system_prompt"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
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
    t.index ["teacher_id"], name: "index_courses_on_teacher_id"
  end

  create_table "enrollments", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "course_id", null: false
    t.boolean "completed"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["course_id"], name: "index_enrollments_on_course_id"
    t.index ["student_id"], name: "index_enrollments_on_student_id"
  end

  create_table "lesson_plans", force: :cascade do |t|
    t.jsonb "content"
    t.enum "status", default: "draft", null: false, enum_type: "lesson_plan_status"
    t.bigint "lesson_id", null: false
    t.bigint "teacher_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lesson_id"], name: "index_lesson_plans_on_lesson_id"
    t.index ["teacher_id"], name: "index_lesson_plans_on_teacher_id"
  end

  create_table "lesson_plans_resources", id: false, force: :cascade do |t|
    t.bigint "lesson_plan_id", null: false
    t.bigint "resource_id", null: false
  end

  create_table "lesson_progresses", force: :cascade do |t|
    t.bigint "student_id", null: false
    t.bigint "lesson_id", null: false
    t.jsonb "chat_history"
    t.jsonb "progress_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lesson_id"], name: "index_lesson_progresses_on_lesson_id"
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

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id"
    t.enum "role", null: false, enum_type: "role_name"
    t.string "content", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
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
    t.bigint "teacher_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["teacher_id"], name: "index_resources_on_teacher_id"
  end

  create_table "settings", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.jsonb "settings", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_settings_on_user_id", unique: true
  end

  create_table "student_reports", force: :cascade do |t|
    t.string "reportable_type", null: false
    t.bigint "reportable_id", null: false
    t.bigint "student_id", null: false
    t.bigint "teacher_id", null: false
    t.bigint "lesson_id", null: false
    t.bigint "enrollment_id", null: false
    t.bigint "course_id", null: false
    t.enum "author_type", null: false, enum_type: "report_author_type"
    t.enum "status", null: false, enum_type: "student_report_status"
    t.jsonb "progress_data"
    t.text "report"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["course_id"], name: "index_student_reports_on_course_id"
    t.index ["enrollment_id"], name: "index_student_reports_on_enrollment_id"
    t.index ["lesson_id"], name: "index_student_reports_on_lesson_id"
    t.index ["reportable_type", "reportable_id"], name: "index_student_reports_on_reportable"
    t.index ["student_id"], name: "index_student_reports_on_student_id"
    t.index ["teacher_id"], name: "index_student_reports_on_teacher_id"
  end

  create_table "tools", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.jsonb "specifications"
    t.bigint "teacher_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["teacher_id"], name: "index_tools_on_teacher_id"
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
  add_foreign_key "conversations", "lesson_progresses"
  add_foreign_key "conversations", "users"
  add_foreign_key "courses", "users", column: "teacher_id"
  add_foreign_key "enrollments", "courses"
  add_foreign_key "enrollments", "users", column: "student_id"
  add_foreign_key "lesson_plans", "lessons"
  add_foreign_key "lesson_plans", "users", column: "teacher_id"
  add_foreign_key "lesson_progresses", "lessons"
  add_foreign_key "lesson_progresses", "users", column: "student_id"
  add_foreign_key "lessons", "courses"
  add_foreign_key "messages", "conversations"
  add_foreign_key "prompts", "users", column: "teacher_id"
  add_foreign_key "resources", "users", column: "teacher_id"
  add_foreign_key "settings", "users"
  add_foreign_key "student_reports", "courses"
  add_foreign_key "student_reports", "enrollments"
  add_foreign_key "student_reports", "lessons"
  add_foreign_key "student_reports", "users", column: "student_id"
  add_foreign_key "student_reports", "users", column: "teacher_id"
  add_foreign_key "tools", "users", column: "teacher_id"
  add_foreign_key "users", "users", column: "teacher_id"
end
