class AdminUser < ApplicationRecord
  has_secure_password

  before_validation :normalize_email_address

  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 12 }, if: -> { password.present? }

  private

  def normalize_email
    self.email_address = email_address.to_s.strip.downcase
  end
end
