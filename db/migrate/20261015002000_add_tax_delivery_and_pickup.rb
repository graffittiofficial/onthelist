class AddTaxDeliveryAndPickup < ActiveRecord::Migration[8.1]
  def change
    create_table :pickup_locations do |t|
      t.string :name, null: false
      t.string :market_code, null: false
      t.string :address_line1, null: false
      t.string :address_line2
      t.string :city, null: false
      t.string :state
      t.string :postal_code, null: false
      t.string :country_code, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :pickup_locations, %i[market_code active]

    add_reference :orders, :pickup_location, foreign_key: true
    add_column :orders, :delivery_method, :string, null: false, default: "shipping"
    add_column :orders, :shipping_address_line1, :string
    add_column :orders, :shipping_address_line2, :string
    add_column :orders, :shipping_city, :string
    add_column :orders, :shipping_state, :string
    add_column :orders, :shipping_postal_code, :string
    add_column :orders, :shipping_country_code, :string
    add_column :orders, :subtotal_cents, :integer, null: false, default: 0
    add_column :orders, :shipping_amount_cents, :integer, null: false, default: 0
    add_column :orders, :tax_amount_cents, :integer, null: false, default: 0
    add_column :orders, :stripe_tax_calculation_id, :string
    add_column :orders, :stripe_payment_intent_id, :string
    add_index :orders, :stripe_payment_intent_id, unique: true
  end
end
