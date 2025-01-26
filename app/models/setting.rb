class Setting < ApplicationRecord
  belongs_to :user

  # add a store_accessor for each settings key to add methods to read/write it
  # e.g. user.settings.pref1="123", user.settings.save!
  store_accessor :settings, :llm_model_name
  store_accessor :settings, :llm_api_access_token

  # for students, if adopted by a teacher, use the teacher's settings
  def llm_model_name
    if user.role_student? && user.teacher
      user.teacher.settings.llm_model_name
    else
      super
    end
  end

  def llm_api_access_token
    if user.role_student? && user.teacher
      user.teacher.settings.llm_api_access_token
    else
      super
    end
  end
end
