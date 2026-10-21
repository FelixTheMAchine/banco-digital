class Notification < ApplicationRecord
  belongs_to :user
  validates :kind, :title, :body, presence: true
  validates :title, length: { maximum: 150 }
  validates :body, length: { maximum: 500 }

  def public_json
    as_json(only: %i[id kind title body read_at created_at])
  end
end
