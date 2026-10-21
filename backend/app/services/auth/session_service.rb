require "digest"
require "securerandom"

module Auth
  class SessionService
    class InvalidCredentials < StandardError; end

    ACCESS_TTL = 15.minutes
    REFRESH_TTL = 30.days

    class << self
      def issue!(user:, family_id: SecureRandom.uuid, mfa_verified_at: nil)
        user.with_lock do
          raise InvalidCredentials unless user.active? && user.email_verified_at.present?

          raise InvalidCredentials if user.mfa_enabled? && mfa_verified_at.nil?
          create_session!(user: user, family_id: family_id, mfa_verified_at: mfa_verified_at)
        end
      end

      def authenticate(raw)
        return unless valid_format?(raw)

        session = AuthSession.find_by(access_digest: digest(raw))
        return unless session

        session.user.with_lock do
          session.reload.lock!
          next unless session.user.active? && session.user.email_verified_at.present?
          next if session.user.mfa_enabled? && session.mfa_verified_at.nil?
          next if session.revoked_at || session.access_expires_at <= Time.current || session.expires_at <= Time.current

          session.update!(last_used_at: Time.current) if session.last_used_at.nil? || session.last_used_at < 5.minutes.ago
          session
        end
      end

      def refresh!(raw)
        raise InvalidCredentials unless valid_format?(raw)

        session = AuthSession.find_by(refresh_digest: digest(raw))
        raise InvalidCredentials unless session

        result = session.user.with_lock do
          session.reload.lock!
          if session.revoked_at
            # Commit this revocation before raising: rolling it back would permit replay.
            AuthSession.where(user_id: session.user_id, family_id: session.family_id, revoked_at: nil)
              .update_all(revoked_at: Time.current)
            AuditLog.create!(user: session.user, action: "auth.refresh_replay", subject_id: session.id)
            nil
          elsif session.expires_at <= Time.current || !session.user.active? || session.user.email_verified_at.nil? || (session.user.mfa_enabled? && session.mfa_verified_at.nil?)
            session.update!(revoked_at: Time.current)
            nil
          else
            session.update!(revoked_at: Time.current, last_used_at: Time.current)
            create_session!(user: session.user, family_id: session.family_id, mfa_verified_at: session.mfa_verified_at)
          end
        end
        raise InvalidCredentials unless result

        result
      end

      def revoke!(session)
        session.user.with_lock do
          AuthSession.where(user_id: session.user_id, family_id: session.family_id, revoked_at: nil)
            .update_all(revoked_at: Time.current)
        end
      end

      def digest(raw)
        Digest::SHA256.hexdigest(raw)
      end

      private

      def valid_format?(raw)
        raw.is_a?(String) && raw.match?(/\A[0-9a-f]{64}\z/)
      end

      def create_session!(user:, family_id:, mfa_verified_at: nil)
        access = SecureRandom.hex(32)
        refresh = SecureRandom.hex(32)
        now = Time.current
        AuthSession.create!(user: user, family_id: family_id,
          access_digest: digest(access), refresh_digest: digest(refresh),
          access_expires_at: now + ACCESS_TTL, expires_at: now + REFRESH_TTL,
          last_used_at: now, mfa_verified_at: mfa_verified_at)
        { access_token: access, refresh_token: refresh, token_type: "Bearer", expires_in: ACCESS_TTL.to_i }
      end
    end
  end
end
