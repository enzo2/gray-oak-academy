class Setting < ApplicationRecord
  belongs_to :user

  # add a store_accessor for each settings key to add methods to read/write it
  # e.g. user.settings.pref1="123", user.settings.save!
  store_accessor :settings, :openrouter_model
  store_accessor :settings, :openrouter_access_token
end
