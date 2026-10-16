class AddProductImagesAndFeaturedCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :product_images do |t|
      t.references :product, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :alt_text, null: false
      t.timestamps
    end
    add_index :product_images, [ :product_id, :position ], unique: true

    add_column :collections, :featured_on_home, :boolean, null: false, default: false
    add_index :collections, :featured_on_home, unique: true, where: "featured_on_home"
  end
end
