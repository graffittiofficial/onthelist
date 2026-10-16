module Storefront
  class CartsController < BaseController
    def show
      @cart = current_cart
      @pending_order = @cart.orders.find_by(status: "pending_payment")
    end
  end
end
