class CartItem < ApplicationRecord
  belongs_to :cart, inverse_of: :items
  belongs_to :variant

  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 20 }
  validates :variant_id, uniqueness: { scope: :cart_id }
end
