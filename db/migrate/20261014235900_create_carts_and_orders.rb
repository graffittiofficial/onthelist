class CreateCartsAndOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :carts do |t|
      t.string :token, null: false
      t.string :market_code, null: false
      t.string :currency, null: false
      t.string :locale, null: false
      t.string :status, null: false, default: "open"
      t.timestamps
    end
    add_index :carts, :token, unique: true

    create_table :cart_items do |t|
      t.references :cart, null: false, foreign_key: true
      t.references :variant, null: false, foreign_key: true
      t.integer :quantity, null: false
      t.timestamps
    end
    add_index :cart_items, %i[cart_id variant_id], unique: true

    create_table :orders do |t|
      t.references :cart, null: false, foreign_key: true
      t.string :public_token, null: false
      t.string :market_code, null: false
      t.string :email, null: false
      t.string :currency, null: false
      t.string :locale, null: false
      t.string :status, null: false, default: "pending_payment"
      t.integer :total_cents, null: false
      t.string :stripe_checkout_session_id
      t.string :stripe_checkout_url
      t.datetime :paid_at
      t.timestamps
    end
    add_index :orders, :public_token, unique: true
    add_index :orders, :stripe_checkout_session_id, unique: true

    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :variant, null: false, foreign_key: true
      t.string :sku, null: false
      t.string :product_name, null: false
      t.string :variant_description, null: false
      t.integer :quantity, null: false
      t.integer :unit_amount_cents, null: false
      t.integer :line_total_cents, null: false
      t.timestamps
    end
  end
end
