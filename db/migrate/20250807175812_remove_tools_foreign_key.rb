class RemoveToolsForeignKey < ActiveRecord::Migration[8.0]
  def change
    remove_reference :tools, :teacher, foreign_key: { to_table: :users }
  end
end
