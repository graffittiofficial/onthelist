module Admin
  class ProductsController < BaseController
    before_action :set_product, only: %i[edit update]

    def index
      @products = Product.includes(:translations, :product_images).order(:slug)
    end

    def new
      @product = Product.new
      build_translations
      build_variant
    end

    def create
      @product = Product.new(product_params)
      @product.collection_ids = collection_ids

      if @product.save
        redirect_to admin_products_path, notice: "Product saved."
      else
        @collections = Collection.order(:slug)
        render :new, status: :unprocessable_content
      end
    end

    def edit
      build_translations
      build_variant if @product.variants.empty?
      @product.variants.each { |variant| add_missing_prices(variant) }
      @collections = Collection.order(:slug)
      @product_image = @product.product_images.build
    end

    def update
      @product.assign_attributes(product_params)
      @product.collection_ids = collection_ids

      if @product.save
        redirect_to admin_products_path, notice: "Product saved."
      else
        @collections = Collection.order(:slug)
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_product
      @product = Product.find(params[:id])
    end

    def build_variant
      variant = @product.variants.build
      add_missing_prices(variant)
      @collections = Collection.order(:slug)
    end

    def add_missing_prices(variant)
      currencies = variant.prices.map(&:currency)
      (Rails.application.config.x.commerce.supported_currencies - currencies).each do |currency|
        variant.prices.build(currency:)
      end
    end

    def build_translations
      locales = @product.translations.map(&:locale)
      (Rails.application.config.x.commerce.supported_locales - locales).each do |locale|
        @product.translations.build(locale:)
      end
    end

    def collection_ids
      Array(params.dig(:product, :collection_ids)).reject(&:blank?)
    end

    def product_params
      params.require(:product).permit(
        :slug, :status, :material, :care_instructions, :sizing_guidance,
        translations_attributes: %i[id locale name description],
        variants_attributes: [
          :id, :sku, :size, :color, :fit, :stock_quantity,
          { prices_attributes: %i[id currency amount_cents sale_amount_cents] }
        ]
      )
    end
  end
end
