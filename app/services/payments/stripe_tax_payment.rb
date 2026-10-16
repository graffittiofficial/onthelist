module Payments
  class StripeTaxPayment
    class ConfigurationError < StandardError; end

    Result = Data.define(:calculation, :payment_intent)

    def self.create(order:)
      api_key = ENV["STRIPE_SECRET_KEY"]
      raise ConfigurationError, "STRIPE_SECRET_KEY is not configured" if api_key.blank?
      raise ConfigurationError, "STRIPE_PUBLISHABLE_KEY is not configured" if ENV["STRIPE_PUBLISHABLE_KEY"].blank?

      market = Rails.application.config.x.commerce.markets.fetch(order.market_code.to_sym)
      calculation = tax_calculation(order:, api_key:, market:)
      update_order_totals(order:, calculation:)

      payment_intent = if order.stripe_payment_intent_id.present?
        Stripe::PaymentIntent.retrieve(order.stripe_payment_intent_id, { api_key: })
      else
        Stripe::PaymentIntent.create(
          {
            amount: calculation.amount_total,
            currency: order.currency.downcase,
            automatic_payment_methods: { enabled: true },
            receipt_email: order.email,
            metadata: { order_id: order.id.to_s },
            hooks: { inputs: { tax: { calculation: calculation.id } } }
          },
          { api_key:, idempotency_key: "onthelist-payment-#{calculation.id}" }
        )
      end
      order.update!(stripe_payment_intent_id: payment_intent.id)

      Result.new(calculation:, payment_intent:)
    end

    def self.tax_calculation(order:, api_key:, market:)
      if order.stripe_tax_calculation_id.present?
        return Stripe::Tax::Calculation.retrieve(order.stripe_tax_calculation_id, { api_key: })
      end

      params = {
        currency: order.currency.downcase,
        customer_details: {
          address: {
            line1: order.shipping_address_line1,
            line2: order.shipping_address_line2,
            city: order.shipping_city,
            state: order.shipping_state,
            postal_code: order.shipping_postal_code,
            country: order.shipping_country_code
          }.compact,
          address_source: "shipping"
        },
        line_items: order.items.map do |item|
          {
            amount: item.line_total_cents,
            quantity: item.quantity,
            reference: "order_item_#{item.id}",
            tax_behavior: market.fetch(:tax_behavior)
          }
        end
      }

      if order.delivery_method == "shipping"
        shipping_rate_id = market[:stripe_shipping_rate_id]
        raise ConfigurationError, "A Stripe shipping rate is not configured for #{order.market_code}" if shipping_rate_id.blank?

        params[:shipping_cost] = { shipping_rate: shipping_rate_id }
      end

      Stripe::Tax::Calculation.create(
        params,
        { api_key:, idempotency_key: "onthelist-tax-#{order.id}" }
      )
    end
    private_class_method :tax_calculation

    def self.update_order_totals(order:, calculation:)
      order.update!(
        stripe_tax_calculation_id: calculation.id,
        subtotal_cents: order.items.sum(:line_total_cents),
        shipping_amount_cents: calculation.shipping_cost&.amount.to_i,
        tax_amount_cents: calculation.tax_amount_exclusive.to_i + calculation.tax_amount_inclusive.to_i,
        total_cents: calculation.amount_total
      )
    end
    private_class_method :update_order_totals
  end
end
