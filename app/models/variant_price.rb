class VariantPrice < ApplicationRecord
  belongs_to :variant, inverse_of: :prices

  validates :currency, presence: true, inclusion: { in: ->(_) { Rails.application.config.x.commerce.supported_currencies } }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sale_amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :currency, uniqueness: { scope: :variant_id }
  validate :sale_price_does_not_exceed_regular_price

  def current_amount_cents
    sale_amount_cents || amount_cents
  end

  private

  def sale_price_does_not_exceed_regular_price
    return if sale_amount_cents.nil? || amount_cents.nil? || sale_amount_cents <= amount_cents

    errors.add(:sale_amount_cents, "must not exceed the regular price")
  end
end
