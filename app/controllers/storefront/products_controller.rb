module Storefront
  class ProductsController < BaseController
    before_action :validate_price_filters, only: :index

    def index
      product_media = { product_images: { image_attachment: :blob } }
      @products = Product.published.includes(:translations, { variants: :prices }, product_media).distinct
      @products = @products.joins(:translations).where(product_translations: { locale: [ I18n.locale.to_s, I18n.default_locale.to_s ] })
      @products = @products.where("product_translations.name ILIKE :query OR product_translations.description ILIKE :query", query: "%#{Product.sanitize_sql_like(params[:q].to_s)}%") if params[:q].present?
      @products = @products.joins(:collections).where(collections: { slug: params[:collection], status: "published" }) if params[:collection].present?
      @products = @products.joins(:variants).where(variants: { size: params[:size] }) if params[:size].present?
      @products = @products.joins(:variants).where(variants: { color: params[:color] }) if params[:color].present?
      @products = @products.joins(:variants).where(variants: { fit: params[:fit] }) if params[:fit].present?
      @products = @products.joins(variants: :prices).where("variants.stock_quantity > 0 AND variant_prices.currency = ?", @currency) if params[:available] == "true"
      apply_price_filters
      @products = sort_products(@products)
      @collections = Collection.published.includes(:translations)
    end

    def show
      @product = Product.published.includes(
        :translations,
        { variants: :prices },
        product_images: { image_attachment: :blob }
      ).find_by!(slug: params[:slug])
      @translation = @product.translation_for(I18n.locale)
      raise ActiveRecord::RecordNotFound unless @translation
    end

    private

    def validate_price_filters
      %i[min_price_cents max_price_cents].each do |key|
        next if params[key].blank? || params[key].to_s.match?(/\A\d+\z/)

        return head :bad_request
      end
    end

    def apply_price_filters
      if params[:min_price_cents].present?
        @products = @products.joins(variants: :prices).where("variant_prices.currency = ? AND COALESCE(variant_prices.sale_amount_cents, variant_prices.amount_cents) >= ?", @currency, params[:min_price_cents])
      end
      if params[:max_price_cents].present?
        @products = @products.joins(variants: :prices).where("variant_prices.currency = ? AND COALESCE(variant_prices.sale_amount_cents, variant_prices.amount_cents) <= ?", @currency, params[:max_price_cents])
      end
    end

    def sort_products(products)
      currency = Product.connection.quote(@currency)
      amount = "(SELECT MIN(COALESCE(variant_prices.sale_amount_cents, variant_prices.amount_cents)) " \
        "FROM variant_prices INNER JOIN variants ON variants.id = variant_prices.variant_id " \
        "WHERE variants.product_id = products.id AND variant_prices.currency = #{currency})"

      case params[:sort]
      when "price_asc"
        products.select("products.*, #{amount} AS sort_price").order(Arel.sql("sort_price ASC"))
      when "price_desc"
        products.select("products.*, #{amount} AS sort_price").order(Arel.sql("sort_price DESC"))
      else
        products.order(created_at: :desc)
      end
    end
  end
end
