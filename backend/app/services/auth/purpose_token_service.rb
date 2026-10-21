require "digest"
require "securerandom"

module Auth
  class PurposeTokenService
    class InvalidToken < StandardError; end

    LIFETIMES = { "email_verification" => 24.hours, "password_reset" => 30.minutes }.freeze

    class << self
      def issue!(user:, purpose:)
        lifetime = LIFETIMES.fetch(purpose)
        user.with_lock do
          raise InvalidToken unless user.active?

          user.purpose_tokens.where(purpose: purpose, consumed_at: nil).update_all(consumed_at: Time.current)
          raw = SecureRandom.hex(32)
          user.purpose_tokens.create!(purpose: purpose, token_digest: Digest::SHA256.hexdigest(raw),
            expires_at: Time.current + lifetime)
          raw
        end
      end

      def consume!(raw, purpose:)
        raise InvalidToken unless raw.is_a?(String) && raw.match?(/\A[0-9a-f]{64}\z/)

        token = PurposeToken.find_by(token_digest: Digest::SHA256.hexdigest(raw), purpose: purpose)
        raise InvalidToken unless token

        token.user.with_lock do
          token.reload.lock!
          raise InvalidToken if token.consumed_at || token.expires_at <= Time.current || !token.user.active?

          yield token.user
          token.update!(consumed_at: Time.current)
        end
      end
    end
  end
end
