class AuthSession < ApplicationRecord
  belongs_to :user
  validates :access_digest, :refresh_digest, :family_id, :access_expires_at, :expires_at, presence: true
  validates :access_digest, :refresh_digest, uniqueness: true
  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
end
