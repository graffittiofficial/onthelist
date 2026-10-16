class CollectionTranslation < ApplicationRecord
  belongs_to :collection, inverse_of: :translations

  validates :locale, :name, presence: true
  validates :locale, uniqueness: { scope: :collection_id }
end
