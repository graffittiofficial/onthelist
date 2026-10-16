class OrderItem < ApplicationRecord
  belongs_to :order, inverse_of: :items
  belongs_to :variant

  validates :sku, :product_name, :variant_description, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_amount_cents, :line_total_cents, numericality: { only_integer: true, greater_than: 0 }
end
