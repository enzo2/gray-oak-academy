class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable

  # Superusers have maximum permissions, and can only be created/elevated manually from the console.
  # Admins only have access to their own students.
  # "Teacher" is not a user role, but but you can use role_teacher? instead of (role_admin? || role_superuser?)
  enum :role, { student: "student", admin: "admin", superuser: "superuser" }, prefix: true

  validates :first_name, presence: true
  validates :last_name, presence: true
  validate :validate_first_user_must_be_admin_or_superuser
  validate :validate_signup_code # A signup code is required for registration, to differentiate teachers and students
  validate :validate_teacher_role
  validate :validate_not_own_teacher
  attr_accessor :signup_code # Allow submission of the signup_code on registration

  after_create :ensure_setting
  after_create :seed_admin_data, if: :role_admin? || :role_superuser?

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
  has_many :authored_reports, class_name: "StudentReport", foreign_key: "teacher_id", inverse_of: :teacher, dependent: :nullify
  has_many :resources, foreign_key: "teacher_id", inverse_of: :teacher, dependent: :nullify # Don't destroy - might be valuable to keep for other teachers
  has_many :prompts, foreign_key: "teacher_id", inverse_of: :teacher, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :applets, dependent: :destroy

  def name
    "#{first_name} #{last_name}"
  end

  # access settings accessors logically e.g. current_user.settings.theme
  def settings
    setting
  end

  def role_teacher?
    role_admin? || role_superuser?
  end

  private

  def validate_teacher_role
    return if teacher.nil?
    errors.add(:teacher, "cannot be a student.") if teacher.role_student?
  end

  def validate_not_own_teacher
    return if teacher.nil?
    errors.add(:teacher, "cannot be yourself") if teacher == self
  end

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

  def validate_first_user_must_be_admin_or_superuser
    return unless new_record?
    return unless User.count.zero?
    errors.add(:role, "must not be a student, because it is the first user.") unless role_superuser? || role_admin?
  end

  def validate_signup_code
    return unless new_record?
    errors.add :signup_code, "is required" unless signup_code.present?

    case role
    when "admin" || "superuser"
      errors.add(:signup_code, "is invalid") unless signup_code == ENV["TEACHER_SIGNUP_CODE"]
    when "student"
      errors.add(:signup_code, "is invalid") unless signup_code == ENV["STUDENT_SIGNUP_CODE"]
    end
  end
end
