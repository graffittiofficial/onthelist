module Webhooks
  class StripeController < ActionController::API
    def create
      webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]
      return head :service_unavailable if webhook_secret.blank?

      event = Stripe::Webhook.construct_event(
        request.raw_post,
        request.headers["Stripe-Signature"],
        webhook_secret
      )

      result = case event.type
      when "payment_intent.succeeded"
        confirm_payment(event.data.object)
      when "payment_intent.payment_failed"
        Rails.logger.info("Stripe PaymentIntent #{event.data.object.id} payment attempt failed.")
        :ok
      when "payment_intent.canceled"
        release_payment(event.data.object)
      else
        :ok
      end

      head result
    rescue Stripe::SignatureVerificationError, JSON::ParserError
      head :bad_request
    end

    private

    def confirm_payment(payment_intent)
      order = order_for_payment(payment_intent)
      order.update!(stripe_payment_intent_id: payment_intent.id) if order.stripe_payment_intent_id.blank?
      valid_payment = payment_intent.status == "succeeded" &&
        payment_intent.metadata&.order_id == order.id.to_s &&
        payment_intent.currency.upcase == order.currency &&
        payment_intent.amount_received == order.total_cents

      unless valid_payment
        Rails.logger.error("Stripe PaymentIntent #{payment_intent.id} did not match order #{order.id}.")
        return :unprocessable_content
      end

      order.payment_confirmed!
      :ok
    end

    def release_payment(payment_intent)
      order = order_for_payment(payment_intent)
      order.update!(stripe_payment_intent_id: payment_intent.id) if order.stripe_payment_intent_id.blank?
      order.payment_failed! unless order.status == "paid"
      :ok
    end

    def order_for_payment(payment_intent)
      Order.find_by(stripe_payment_intent_id: payment_intent.id) ||
        Order.find_by!(id: payment_intent.metadata&.order_id)
    end
  end
end
