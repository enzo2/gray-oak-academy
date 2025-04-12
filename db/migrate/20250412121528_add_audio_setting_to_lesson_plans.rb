class AddAudioSettingToLessonPlans < ActiveRecord::Migration[8.0]
  def up
    create_enum :audio_setting, [ "disabled", "enabled", "audio-only" ]
    change_table :lesson_plans do |t|
      t.enum :audio, enum_type: :audio_setting, default: "disabled", null: false
    end
  end
end
