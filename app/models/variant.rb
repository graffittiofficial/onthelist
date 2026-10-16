class Variant < ApplicationRecord
  belongs_to :product, inverse_of: :variants
  has_many :prices, class_name: "VariantPrice", dependent: :destroy, inverse_of: :variant

  accepts_nested_attributes_for :prices

  validates :sku, presence: true, uniqueness: true
  validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :available, -> { where("stock_quantity > 0") }

  def price_for(currency)
    prices.find_by(currency:)
  end
end
