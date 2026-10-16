class OrderExpirationJob < ApplicationJob
  retry_on Stripe::APIConnectionError, wait: 30.seconds, attempts: 5

  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order&.status == "pending_payment"

    if order.payment_expires_at > Time.current
      self.class.set(wait_until: order.payment_expires_at).perform_later(order.id)
      return
    end

    unless order.stripe_payment_intent_id.present?
      order.payment_expired!
      return
    end

    api_key = ENV.fetch("STRIPE_SECRET_KEY")
    payment_intent = Stripe::PaymentIntent.retrieve(order.stripe_payment_intent_id, { api_key: })
    case payment_intent.status
    when "succeeded"
      order.payment_confirmed!
    when "processing"
      order.update!(payment_expires_at: 5.minutes.from_now)
      self.class.set(wait_until: order.payment_expires_at).perform_later(order.id)
    when "canceled"
      order.payment_expired!
    else
      Stripe::PaymentIntent.cancel(payment_intent.id, {}, { api_key: })
      order.payment_expired!
    end
  end
end
