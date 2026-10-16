module Storefront
  class CollectionsController < BaseController
    def show
      @collection = Collection.published.includes(
        :translations,
        products: [ :translations, { variants: :prices }, { product_images: { image_attachment: :blob } }]
      ).find_by!(slug: params[:slug])
      @translation = @collection.translation_for(I18n.locale)
      raise ActiveRecord::RecordNotFound unless @translation
      @products = @collection.products.published
    end
  end
end
