class Cart < ApplicationRecord
  STATUSES = %w[open checkout completed].freeze

  has_many :items, class_name: "CartItem", dependent: :destroy, inverse_of: :cart
  has_many :variants, through: :items
  has_many :orders, dependent: :restrict_with_exception

  validates :token, :market_code, :currency, :locale, presence: true
  validates :status, inclusion: { in: STATUSES }

  def total_cents
    items.includes(variant: :prices).sum do |item|
      price = item.variant.price_for(currency)
      price ? price.current_amount_cents * item.quantity : 0
    end
  end
end
