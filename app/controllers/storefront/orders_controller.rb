module Storefront
  class OrdersController < BaseController
    def show
      @order = Order.find_by!(public_token: params[:token])
      I18n.locale = @order.locale.to_sym
    end
  end
end
