class Order < ApplicationRecord
  STATUSES = %w[pending_payment paid payment_failed expired].freeze

  belongs_to :cart
  belongs_to :pickup_location, optional: true
  has_many :items, class_name: "OrderItem", dependent: :restrict_with_exception, inverse_of: :order

  validates :delivery_method, inclusion: { in: %w[shipping pickup] }
  validates :shipping_address_line1, :shipping_city, :shipping_postal_code, :shipping_country_code,
    presence: true, if: -> { delivery_method == "shipping" }
  validates :pickup_location, presence: true, if: -> { delivery_method == "pickup" }
  validates :subtotal_cents, :shipping_amount_cents, :tax_amount_cents,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :public_token, :email, :market_code, :currency, :locale, :payment_expires_at, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :status, inclusion: { in: STATUSES }
  validates :total_cents, numericality: { only_integer: true, greater_than: 0 }

  def payment_confirmed!
    Order.transaction do
      cart.with_lock do
        lock!
        if status == "pending_payment"
          update!(status: "paid", paid_at: Time.current)
          cart.update!(status: "completed")
        end
      end
    end
  end

  def payment_expired!
    release_reservation!("expired")
  end

  def payment_failed!
    release_reservation!("payment_failed")
  end

  private

  def release_reservation!(new_status)
    Order.transaction do
      cart.with_lock do
        lock!
        if status == "pending_payment"
          items.each do |item|
            variant = item.variant
            variant.with_lock { variant.increment!(:stock_quantity, item.quantity) }
          end
          update!(status: new_status)
          cart.update!(status: "open")
        end
      end
    end
  end
end
