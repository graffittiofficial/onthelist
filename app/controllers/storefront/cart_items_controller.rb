module Storefront
  class CartItemsController < BaseController
    class CartLocked < StandardError; end
    before_action :set_cart
    before_action :ensure_cart_is_open

    def create
      variant = Variant.joins(:product).merge(Product.published).find(params[:variant_id])
      quantity = parse_quantity
      return render_invalid if quantity.nil?

      unavailable = false
      CartItem.transaction do
        @cart.with_lock do
          raise CartLocked unless @cart.status == "open"
          variant.with_lock do
            price = variant.price_for(@currency)
            item = @cart.items.find_or_initialize_by(variant:)
            new_quantity = item.quantity.to_i + quantity
            if !price || variant.stock_quantity < new_quantity || new_quantity > 20
              unavailable = true
            else
              item.update!(quantity: new_quantity)
            end
          end
        end
      end
      return render_unavailable if unavailable

      redirect_to cart_path, notice: "Added to your Cart."
    rescue CartLocked
      redirect_to cart_path, alert: "Your Cart is being checked out. Complete or wait for that payment before changing it."
    end

    def update
      quantity = parse_quantity
      return render_invalid if quantity.nil? || quantity < 1

      item = @cart.items.includes(variant: :prices).find(params[:id])
      unavailable = false
      @cart.with_lock do
        raise CartLocked unless @cart.status == "open"
        item.variant.with_lock do
          price = item.variant.price_for(@currency)
          if !price || item.variant.stock_quantity < quantity
            unavailable = true
          else
            item.update!(quantity:)
          end
        end
      end
      return render_unavailable if unavailable

      redirect_to cart_path, notice: "Cart updated."
    rescue CartLocked
      redirect_to cart_path, alert: "Your Cart is being checked out. Complete or wait for that payment before changing it."
    end

    def destroy
      @cart.with_lock do
        raise CartLocked unless @cart.status == "open"
        @cart.items.find(params[:id]).destroy!
      end
      redirect_to cart_path, notice: "Removed from your Cart."
    rescue CartLocked
      redirect_to cart_path, alert: "Your Cart is being checked out. Complete or wait for that payment before changing it."
    end

    private

    def set_cart
      @cart = current_cart
    end

    def ensure_cart_is_open
      return if @cart.status == "open"

      redirect_to cart_path, alert: "Your Cart is being checked out. Complete or wait for that payment before changing it."
    end

    def parse_quantity
      value = params.dig(:cart_item, :quantity) || params[:quantity]
      Integer(value, 10)
    rescue ArgumentError, TypeError
      nil
    end

    def render_invalid
      head :unprocessable_content
    end

    def render_unavailable
      redirect_to cart_path, alert: "That Variant is unavailable in the requested quantity or Currency."
    end
  end
end
