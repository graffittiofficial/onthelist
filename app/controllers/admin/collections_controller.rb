module Admin
  class CollectionsController < BaseController
    before_action :set_collection, only: %i[edit update]

    def index
      @collections = Collection.includes(:translations).order(:slug)
    end

    def new
      @collection = Collection.new
      build_translations
      @products = Product.order(:slug)
    end

    def create
      @collection = Collection.new(collection_params)
      @collection.product_ids = product_ids

      if save_collection
        redirect_to admin_collections_path, notice: "Collection saved."
      else
        @products = Product.order(:slug)
        render :new, status: :unprocessable_content
      end
    end

    def edit
      build_translations
      @products = Product.order(:slug)
    end

    def update
      @collection.assign_attributes(collection_params)
      @collection.product_ids = product_ids

      if save_collection
        redirect_to admin_collections_path, notice: "Collection saved."
      else
        @products = Product.order(:slug)
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_collection
      @collection = Collection.find(params[:id])
    end

    def build_translations
      locales = @collection.translations.map(&:locale)
      (Rails.application.config.x.commerce.supported_locales - locales).each do |locale|
        @collection.translations.build(locale:)
      end
    end

    def product_ids
      Array(params.dig(:collection, :product_ids)).reject(&:blank?)
    end

    def collection_params
      params.require(:collection).permit(
        :slug, :status, :featured_on_home, translations_attributes: %i[id locale name description]
      )
    end

    def save_collection
      return false unless @collection.valid?

      Collection.transaction do
        Collection.featured_on_home.where.not(id: @collection.id).update_all(featured_on_home: false) if @collection.featured_on_home?
        @collection.save!
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end
  end
end
