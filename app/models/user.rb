class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :trackable

  enum :role, { student: "student", admin: "admin" }, prefix: true

  before_create :set_default_role

  def set_default_role
    self.role = User.count.zero? ? :admin : :student
  end
end
