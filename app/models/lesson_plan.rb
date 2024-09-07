class LessonPlan < ApplicationRecord
  belongs_to :lesson
  belongs_to :teacher, class_name: "User", inverse_of: :lesson_plans
  has_one :course, through: :lesson
  has_and_belongs_to_many :resources

  enum :status, { draft: "draft", published: "published", archived: "archived" }, prefix: true
end
