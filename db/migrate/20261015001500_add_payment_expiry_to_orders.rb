class AddPaymentExpiryToOrders < ActiveRecord::Migration[8.1]
  def up
    add_column :orders, :payment_expires_at, :datetime
    execute "UPDATE orders SET payment_expires_at = CURRENT_TIMESTAMP WHERE payment_expires_at IS NULL"
    change_column_null :orders, :payment_expires_at, false
    add_index :orders, :payment_expires_at
  end

  def down
    remove_index :orders, :payment_expires_at
    remove_column :orders, :payment_expires_at
  end
end
