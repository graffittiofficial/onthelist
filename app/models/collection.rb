class Collection < ApplicationRecord
  STATUSES = %w[draft published].freeze

  has_many :translations, class_name: "CollectionTranslation", dependent: :destroy, inverse_of: :collection
  has_many :product_collections, dependent: :destroy
  has_many :products, through: :product_collections

  accepts_nested_attributes_for :translations, reject_if: ->(attributes) { attributes["name"].blank? }

  validates :slug, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :published, -> { where(status: "published") }
  scope :featured_on_home, -> { where(featured_on_home: true) }

  def translation_for(locale)
    translations.find_by(locale:) || translations.find_by(locale: I18n.default_locale.to_s)
  end
end
