class AddEmbeddingToMemories < ActiveRecord::Migration[8.0]
  def change
    add_column :memories, :embedding, :vector
  end
end
