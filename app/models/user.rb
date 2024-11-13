class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable

  enum :role, { student: "student", admin: "admin" }, prefix: true
  before_create :set_default_role
  after_create :ensure_setting
  after_create :seed_admin_data, if: :role_admin?

  validates :first_name, presence: true
  validates :last_name, presence: true
  validate :validate_admin_signup_code, if: :role_admin?

  has_many :students, class_name: "User", foreign_key: "teacher_id", inverse_of: :teacher
  belongs_to :teacher, class_name: "User", optional: true, inverse_of: :students
  has_one_attached :profile_picture, dependent: :destroy
  has_one :setting, dependent: :destroy
  has_many :enrollments, foreign_key: "student_id", inverse_of: :student
  has_many :courses, through: :enrollments, inverse_of: :students
  has_many :taught_courses, class_name: "Course", foreign_key: "teacher_id", inverse_of: :teacher
  has_many :lessons, through: :courses
  has_many :lesson_plans, foreign_key: "teacher_id", inverse_of: :teacher
  has_many :lesson_progresses, foreign_key: "student_id", inverse_of: :student
  has_many :student_reports, as: :reportable # for any generic student reports outside of any specific enrollment or lesson
  has_many :authored_reports, class_name: "StudentReport", foreign_key: "teacher_id", inverse_of: :teacher
  has_many :resources, foreign_key: "teacher_id", inverse_of: :teacher
  has_many :prompts, foreign_key: "teacher_id", inverse_of: :teacher
  has_many :tools, foreign_key: "teacher_id", inverse_of: :teacher
  has_many :conversations

  attr_accessor :signup_code

  def name
    "#{first_name} #{last_name}"
  end

  # access settings accessors logically e.g. current_user.settings.theme
  def settings
    setting
  end

  private

  def set_default_role
    self.role = :admin if User.count.zero?
  end

  def ensure_setting
    create_setting! if setting.nil?
  end

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

  def validate_admin_signup_code
    return unless role_admin?
    unless signup_code.present? && signup_code == ENV["TEACHER_SIGNUP_CODE"]
      errors.add(:signup_code, "is invalid")
    end
  end
end
