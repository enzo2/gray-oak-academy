class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable

  enum :role, { student: "student", admin: "admin" }, prefix: true
  before_create :set_default_role

  has_many :students, class_name: "User", foreign_key: "teacher_id", inverse_of: :teacher
  belongs_to :teacher, class_name: "User", optional: true, inverse_of: :students
  has_one_attached :profile_picture

  has_many :enrollments, foreign_key: "student_id", inverse_of: :student
  has_many :courses, through: :enrollments, inverse_of: :students
  has_many :taught_courses, class_name: "Course", foreign_key: "teacher_id", inverse_of: :teacher
  has_many :lessons, through: :courses
  has_many :lesson_plans, foreign_key: "teacher_id", inverse_of: :teacher
  has_many :lesson_progresses, foreign_key: "student_id", inverse_of: :student
  has_many :student_reports, foreign_key: "student_id", inverse_of: :student
  has_many :authored_reports, class_name: "StudentReport", foreign_key: "teacher_id", inverse_of: :teacher
  has_many :resources, foreign_key: "teacher_id", inverse_of: :teacher
  has_many :prompts, foreign_key: "teacher_id", inverse_of: :teacher
  has_many :tools, foreign_key: "teacher_id", inverse_of: :teacher

  private

  # For initial setup, first account is set as admin
  def set_default_role
    self.role = User.count.zero? ? :admin : :student
  end
end
