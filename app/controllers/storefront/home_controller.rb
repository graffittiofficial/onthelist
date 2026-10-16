module Storefront
  class HomeController < BaseController
    def index
      product_media = { product_images: { image_attachment: :blob } }
      @featured_collection = Collection.published.featured_on_home
        .includes(:translations, products: [ :translations, product_media ])
        .first
      @featured_product = @featured_collection&.products&.published&.includes(product_media)&.order(:id)&.first
      @collections = Collection.published.includes(:translations, products: product_media).order(:slug)
    end
  end
end
