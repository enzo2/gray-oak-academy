class Resource < ApplicationRecord
  has_and_belongs_to_many :lesson_plans
  has_one_attached :file
end
