module Storefront
  class CheckoutsController < BaseController
    class UnavailableCart < StandardError; end
    class InvalidDeliveryDetails < StandardError; end

    before_action :load_checkout_context

    def show
      @order = @pending_order
    end

    def create
      return render :show, status: :unprocessable_content if @cart.items.empty?

      order = @pending_order || begin
        email = params[:email].to_s.strip.downcase
        raise InvalidDeliveryDetails unless email.match?(URI::MailTo::EMAIL_REGEXP)

        delivery_details = delivery_params
        order = reserve_cart!(email:, delivery_details:)
        order
      end
      OrderExpirationJob.set(wait_until: order.payment_expires_at).perform_later(order.id)

      payment = Payments::StripeTaxPayment.create(order:)
      @order = order
      @payment_client_secret = payment.payment_intent.client_secret
      @publishable_key = ENV.fetch("STRIPE_PUBLISHABLE_KEY")
      if payment.payment_intent.status == "succeeded"
        order.payment_confirmed!
        return redirect_to order_path(order.public_token, market: order.market_code)
      end
      render :show
    rescue InvalidDeliveryDetails
      flash.now[:alert] = "Enter a valid email address and complete the selected delivery details."
      render :show, status: :unprocessable_content
    rescue UnavailableCart
      @cart.reload
      @pending_order = nil
      flash.now[:alert] = "A Variant is no longer available at the selected price. Your Cart has not changed."
      render :show, status: :unprocessable_content
    rescue Stripe::APIConnectionError => error
      Rails.logger.error("Stripe payment setup outcome is unknown: #{error.class}: #{error.message}")
      @order = order
      @pending_order = order
      flash.now[:alert] = "We could not confirm payment setup yet. Retry to safely resume."
      render :show, status: :bad_gateway
    rescue Payments::StripeTaxPayment::ConfigurationError, Stripe::StripeError => error
      Rails.logger.error("Stripe Tax or PaymentIntent setup failed: #{error.class}: #{error.message}")
      order&.payment_failed!
      @pending_order = nil
      flash.now[:alert] = "Secure payment is temporarily unavailable. Your Cart is available to try again."
      render :show, status: :bad_gateway
    end

    private

    def load_checkout_context
      @cart = current_cart
      @pending_order = @cart.orders.find_by(status: "pending_payment")
      @pickup_locations = PickupLocation.active.where(market_code: @market_code).order(:name)
    end

    def delivery_params
      delivery_method = params[:delivery_method]
      case delivery_method
      when "shipping"
        address = params.fetch(:shipping_address, ActionController::Parameters.new)
          .permit(:line1, :line2, :city, :state, :postal_code)
          .to_h
        raise InvalidDeliveryDetails if %w[line1 city postal_code].any? { |key| address[key].blank? }
        {
          delivery_method:,
          shipping_address_line1: address.fetch("line1"),
          shipping_address_line2: address["line2"],
          shipping_city: address.fetch("city"),
          shipping_state: address["state"],
          shipping_postal_code: address.fetch("postal_code"),
          shipping_country_code: @market_code
        }
      when "pickup"
        pickup_location = @pickup_locations.find_by(id: params[:pickup_location_id])
        raise InvalidDeliveryDetails unless pickup_location

        {
          delivery_method:,
          pickup_location:,
          shipping_address_line1: pickup_location.address_line1,
          shipping_address_line2: pickup_location.address_line2,
          shipping_city: pickup_location.city,
          shipping_state: pickup_location.state,
          shipping_postal_code: pickup_location.postal_code,
          shipping_country_code: pickup_location.country_code
        }
      else
        raise InvalidDeliveryDetails
      end
    end

    def reserve_cart!(email:, delivery_details:)
      order = nil
      Order.transaction do
        @cart.lock!
        raise UnavailableCart unless @cart.status == "open"

        cart_items = @cart.items.includes(variant: [ :product, :prices ]).to_a
        variants = Variant.where(id: cart_items.map(&:variant_id)).order(:id).lock.index_by(&:id)
        prepared_items = cart_items.map do |item|
          variant = variants.fetch(item.variant_id)
          price = variant.price_for(@currency)
          product = variant.product
          translation = product.translation_for(I18n.locale)
          raise UnavailableCart unless product.status == "published" &&
            translation && price && variant.stock_quantity >= item.quantity

          {
            cart_item: item,
            variant:,
            price:,
            product_name: translation.name,
            variant_description: [ variant.color, variant.size, variant.fit ].compact_blank.join(" / ").presence || variant.sku
          }
        end

        subtotal_cents = prepared_items.sum { |item| item.fetch(:price).current_amount_cents * item.fetch(:cart_item).quantity }
        raise UnavailableCart unless subtotal_cents.positive?

        order = @cart.orders.create!(
          {
            public_token: SecureRandom.urlsafe_base64(32),
            market_code: @market_code,
            email:,
            currency: @currency,
            locale: I18n.locale.to_s,
            subtotal_cents:,
            total_cents: subtotal_cents,
            payment_expires_at: 35.minutes.from_now
          }.merge(delivery_details)
        )
        prepared_items.each do |entry|
          cart_item = entry.fetch(:cart_item)
          variant = entry.fetch(:variant)
          unit_amount = entry.fetch(:price).current_amount_cents
          order.items.create!(
            variant:,
            sku: variant.sku,
            product_name: entry.fetch(:product_name),
            variant_description: entry.fetch(:variant_description),
            quantity: cart_item.quantity,
            unit_amount_cents: unit_amount,
            line_total_cents: unit_amount * cart_item.quantity
          )
          variant.update!(stock_quantity: variant.stock_quantity - cart_item.quantity)
        end
        @cart.update!(status: "checkout")
      end
      order
    end
  end
end
