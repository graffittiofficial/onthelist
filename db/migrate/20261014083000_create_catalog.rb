class CreateCatalog < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.string :slug, null: false
      t.string :status, null: false, default: "draft"
      t.string :material
      t.text :care_instructions
      t.text :sizing_guidance
      t.timestamps
    end
    add_index :products, :slug, unique: true

    create_table :product_translations do |t|
      t.references :product, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :name, null: false
      t.text :description
      t.timestamps
    end
    add_index :product_translations, %i[product_id locale], unique: true

    create_table :variants do |t|
      t.references :product, null: false, foreign_key: true
      t.string :sku, null: false
      t.string :size
      t.string :color
      t.string :fit
      t.integer :stock_quantity, null: false, default: 0
      t.timestamps
    end
    add_index :variants, :sku, unique: true

    create_table :variant_prices do |t|
      t.references :variant, null: false, foreign_key: true
      t.string :currency, null: false
      t.integer :amount_cents, null: false
      t.integer :sale_amount_cents
      t.timestamps
    end
    add_index :variant_prices, %i[variant_id currency], unique: true

    create_table :collections do |t|
      t.string :slug, null: false
      t.string :status, null: false, default: "draft"
      t.timestamps
    end
    add_index :collections, :slug, unique: true

    create_table :collection_translations do |t|
      t.references :collection, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :name, null: false
      t.text :description
      t.timestamps
    end
    add_index :collection_translations, %i[collection_id locale], unique: true

    create_table :product_collections do |t|
      t.references :product, null: false, foreign_key: true
      t.references :collection, null: false, foreign_key: true
      t.timestamps
    end
    add_index :product_collections, %i[product_id collection_id], unique: true
  end
end
