class User < ApplicationRecord
  has_secure_password
  before_validation :normalize_email_address

  has_many :sessions, dependent: :destroy

  validates :email_address, presence: true, uniqueness: true
  normalizes :email_address, with: ->(e) { e.strip.downcase }
  validates :password, length: { minimum: 12 }, if: -> { password.present? }

  private

  def normalize_email_address
    self.email_address = email_address.to_s.strip.downcase
  end
end
