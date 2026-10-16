class PickupLocation < ApplicationRecord
  validates :name, :market_code, :address_line1, :city, :postal_code, :country_code, presence: true
  validates :market_code, inclusion: { in: ->(_) { Rails.application.config.x.commerce.markets.keys.map(&:to_s) } }
  validates :country_code, inclusion: { in: ->(location) { [ location.market_code ] } }

  scope :active, -> { where(active: true) }
end
