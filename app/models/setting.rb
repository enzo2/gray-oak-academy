class Setting < ApplicationRecord
  belongs_to :user

  # add a store_accessor for each settings key to add methods to read/write it
  # e.g. user.settings.pref1="123", user.settings.save!
  store_accessor :settings, :openrouter_model
  store_accessor :settings, :openrouter_access_token

  # for students, use the teacher's settings
  def openrouter_model
    if user.role_student? && user.teacher
      user.teacher.settings.openrouter_model
    else
      super
    end
  end

  def openrouter_access_token
    if user.role_student? && user.teacher
      user.teacher.settings.openrouter_access_token
    else
      super
    end
  end
end
