class ChangeLessonPlanAudioDefault < ActiveRecord::Migration[8.0]
  def change
    change_column_default :lesson_plans, :audio, from: "disabled", to: "enabled"
  end
end
