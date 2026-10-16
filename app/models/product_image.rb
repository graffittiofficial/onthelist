class ProductImage < ApplicationRecord
  MAX_IMAGES_PER_PRODUCT = 8
  MAX_FILE_SIZE = 10.megabytes
  ACCEPTED_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze

  belongs_to :product, inverse_of: :product_images
  has_one_attached :image, dependent: :purge_later

  before_validation :set_position, on: :create

  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :alt_text, presence: true, length: { maximum: 250 }
  validate :gallery_has_room, on: :create
  validate :image_is_acceptable

  private

  def set_position
    self.position = product.product_images.maximum(:position).to_i + 1 if position.blank?
  end

  def gallery_has_room
    return unless product && product.product_images.count >= MAX_IMAGES_PER_PRODUCT

    errors.add(:base, "A Product can have at most #{MAX_IMAGES_PER_PRODUCT} images.")
  end

  def image_is_acceptable
    unless image.attached?
      errors.add(:image, "must be attached")
      return
    end

    return if ACCEPTED_CONTENT_TYPES.include?(image.blob.content_type) && image.blob.byte_size <= MAX_FILE_SIZE

    errors.add(:image, "must be a JPEG, PNG, or WebP file no larger than 10 MB")
  end
end
