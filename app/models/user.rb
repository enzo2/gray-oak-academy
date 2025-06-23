class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable

  enum :role, { student: "student", admin: "admin" }, prefix: true

  validates :first_name, presence: true
  validates :last_name, presence: true
  validate :validate_first_user_must_be_admin
  validate :validate_signup_code
  attr_accessor :signup_code # Allow submission of the signup_code on registration

  after_create :ensure_setting
  after_create :seed_admin_data, if: :role_admin?

  has_many :students, class_name: "User", foreign_key: "teacher_id", inverse_of: :teacher
  belongs_to :teacher, class_name: "User", optional: true, inverse_of: :students
  has_one_attached :profile_picture, dependent: :destroy
  has_one :setting, dependent: :destroy
  has_many :enrollments, foreign_key: "student_id", inverse_of: :student
  has_many :courses, through: :enrollments, inverse_of: :students
  has_many :taught_courses, class_name: "Course", foreign_key: "teacher_id", inverse_of: :teacher
  has_many :lessons, through: :courses
  has_many :lesson_plans, foreign_key: "teacher_id", inverse_of: :teacher
  has_many :lesson_progresses, foreign_key: "student_id", inverse_of: :student, dependent: :destroy
  has_many :student_reports, foreign_key: "student_id", inverse_of: :student, dependent: :destroy # Retrieves all student reports. When querying, use scopes to narrow by reportable_type.
  has_many :user_context_reports, class_name: "StudentReport", as: :reportable # for generic reports; specific ones for course or completed lessons would be associated via ENROLLMENTS, or LESSON_PROGRESS
  has_many :authored_reports, class_name: "StudentReport", foreign_key: "teacher_id", inverse_of: :teacher
  has_many :resources, foreign_key: "teacher_id", inverse_of: :teacher
  has_many :prompts, foreign_key: "teacher_id", inverse_of: :teacher, dependent: :destroy
  # has_many :tools, foreign_key: "teacher_id", inverse_of: :teacher, dependent: :destroy
  has_many :conversations
  has_many :applets

  def name
    "#{first_name} #{last_name}"
  end

  # access settings accessors logically e.g. current_user.settings.theme
  def settings
    setting
  end

  private

  def ensure_setting
    create_setting! if setting.nil?
  end

  # Add seed data for teachers upon account creation
  def seed_admin_data
    yaml_file = Rails.root.join("config", "admin_user_seed_data.yml")
    data = YAML.load_file(yaml_file)
    process_initial_data(data)
  end

  def process_initial_data(data)
    data["resources"].each do |resource|
      # add the resource to db, with user set to current user
      Resource.create!(resource.merge(teacher: self))
    end
  end

  def validate_first_user_must_be_admin
    return unless new_record?
    return unless User.count.zero?
    errors.add(:role, "must be teacher for the first user.") unless role_admin?
  end

  def validate_signup_code
    return unless new_record?
    errors.add :signup_code, "is required" unless signup_code.present?

    case role
    when "admin"
      errors.add(:signup_code, "is invalid") unless signup_code == ENV["TEACHER_SIGNUP_CODE"]
    when "student"
      errors.add(:signup_code, "is invalid") unless signup_code == ENV["STUDENT_SIGNUP_CODE"]
    end
  end
end
