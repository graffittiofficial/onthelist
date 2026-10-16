class ProductTranslation < ApplicationRecord
  belongs_to :product, inverse_of: :translations

  validates :locale, :name, presence: true
  validates :locale, uniqueness: { scope: :product_id }
end
