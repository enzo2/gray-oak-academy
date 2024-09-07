class CreatePrompts < ActiveRecord::Migration[7.2]
  def change
    create_table :prompts do |t|
      t.string :title
      t.text :prompt

      t.timestamps
    end
  end
end
