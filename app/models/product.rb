class Product < ApplicationRecord
  STATUSES = %w[draft published].freeze

  has_many :translations, class_name: "ProductTranslation", dependent: :destroy, inverse_of: :product
  has_many :variants, dependent: :destroy, inverse_of: :product
  has_many :product_images, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :product
  has_many :product_collections, dependent: :destroy
  has_many :collections, through: :product_collections

  accepts_nested_attributes_for :translations, reject_if: ->(attributes) { attributes["name"].blank? }
  accepts_nested_attributes_for :variants

  validates :slug, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :published, -> { where(status: "published") }

  def translation_for(locale)
    translations.find_by(locale:) || translations.find_by(locale: I18n.default_locale.to_s)
  end
end
