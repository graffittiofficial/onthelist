module Storefront
  class BaseController < ApplicationController
    allow_unauthenticated_access
    before_action :set_market

    private

    def set_market
      markets = Rails.application.config.x.commerce.markets
      market_code = params.fetch(:market, "US").to_s.upcase
      market = markets[market_code.to_sym]
      return head :bad_request unless market

      @market_code = market_code
      @currency = market.fetch(:currency)
      I18n.locale = market.fetch(:locale).to_sym
    end

    def current_cart
      tokens = session[:cart_tokens] ||= {}
      token = tokens[@market_code] ||= SecureRandom.hex(32)
      cart = Cart.find_or_create_by!(token:) do |new_cart|
        new_cart.market_code = @market_code
        new_cart.currency = @currency
        new_cart.locale = I18n.locale.to_s
      end
      if cart.status == "completed"
        tokens[@market_code] = token = SecureRandom.hex(32)
        cart = Cart.create!(
          token:,
          market_code: @market_code,
          currency: @currency,
          locale: I18n.locale.to_s
        )
      end
      cart
    end
  end
end
