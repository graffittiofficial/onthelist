module Admin
  class VariantsController < BaseController
    before_action :set_product
    before_action :set_variant, only: %i[edit update]

    def new
      @variant = @product.variants.build
      add_missing_prices
    end

    def create
      @variant = @product.variants.build(variant_params)

      if @variant.save
        redirect_to edit_admin_product_path(@product), notice: "Variant saved."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
      add_missing_prices
    end

    def update
      @variant.assign_attributes(variant_params)

      if @variant.save
        redirect_to edit_admin_product_path(@product), notice: "Variant saved."
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_product
      @product = Product.find(params[:product_id])
    end

    def set_variant
      @variant = @product.variants.find(params[:id])
    end

    def add_missing_prices
      currencies = @variant.prices.map(&:currency)
      (Rails.application.config.x.commerce.supported_currencies - currencies).each do |currency|
        @variant.prices.build(currency:)
      end
    end

    def variant_params
      params.require(:variant).permit(
        :sku, :size, :color, :fit, :stock_quantity,
        prices_attributes: %i[id currency amount_cents sale_amount_cents]
      )
    end
  end
end
