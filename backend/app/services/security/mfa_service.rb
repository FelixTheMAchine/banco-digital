require "digest"
require "securerandom"

module Security
  class MfaService
    class InvalidCode < StandardError; end
    class AlreadyEnabled < StandardError; end
    class Required < StandardError; end
    PENDING_TTL = 10.minutes
    ISSUER = "Aurora Banco Simulado".freeze

    class << self
      def start_enrollment!(user:, session:, password:)
        user.with_lock do
          valid_session!(user, session)
          raise InvalidCode unless user.authenticate(password)
          raise AlreadyEnabled if user.mfa_enabled?
          secret = ROTP::Base32.random_base32
          user.update!(mfa_pending_secret: secret, mfa_pending_expires_at: Time.current + PENDING_TTL)
          audit!(user, "security.mfa_enrollment_started")
          { secret: secret, provisioning_uri: totp(secret).provisioning_uri(user.email) }
        end
      end

      def enable!(user:, session:, code:)
        user.with_lock do
          valid_session!(user, session)
          raise AlreadyEnabled if user.mfa_enabled?
          raise InvalidCode unless user.mfa_pending_secret.present? && user.mfa_pending_expires_at && user.mfa_pending_expires_at > Time.current
          timestamp = verify_totp!(user.mfa_pending_secret, code, after: nil)
          codes = Array.new(8) { SecureRandom.hex(16) }
          user.update!(mfa_secret: user.mfa_pending_secret, mfa_pending_secret: nil,
            mfa_pending_expires_at: nil, mfa_enabled_at: Time.current, mfa_last_otp_at: timestamp,
            mfa_recovery_digests: codes.map { |item| digest(item) })
          user.auth_sessions.where.not(id: session.id).where(revoked_at: nil).update_all(revoked_at: Time.current)
          session.update!(mfa_verified_at: Time.current)
          audit!(user, "security.mfa_enabled")
          codes
        end
      end

      # Caller may hold the user lock; with_lock nests in the same transaction.
      def verify!(user:, code: nil, recovery_code: nil)
        user.with_lock do
          raise InvalidCode unless user.active? && user.email_verified_at.present?
          raise Required unless user.mfa_enabled?
          if recovery_code.present?
            raise InvalidCode unless recovery_code.is_a?(String) && recovery_code.match?(/\A[0-9a-f]{32}\z/)
            expected = digest(recovery_code)
            remaining = user.mfa_recovery_digests.dup
            index = remaining.index { |stored| ActiveSupport::SecurityUtils.secure_compare(stored, expected) }
            raise InvalidCode unless index
            remaining.delete_at(index)
            user.update!(mfa_recovery_digests: remaining)
            audit!(user, "security.mfa_recovery_used")
          else
            timestamp = verify_totp!(user.mfa_secret, code, after: user.mfa_last_otp_at)
            user.update!(mfa_last_otp_at: timestamp)
          end
          true
        end
      end

      def step_up!(user:, session:, code: nil, recovery_code: nil)
        user.with_lock do
          valid_session!(user, session)
          verify!(user: user, code: code, recovery_code: recovery_code)
          session.update!(mfa_verified_at: Time.current)
          audit!(user, "security.mfa_verified")
        end
      end

      def disable!(user:, session:, password:, code: nil, recovery_code: nil)
        user.with_lock do
          valid_session!(user, session)
          raise InvalidCode unless user.authenticate(password)
          # Administrators cannot downgrade their account to password-only authentication.
          raise InvalidCode if user.role == "admin"
          verify!(user: user, code: code, recovery_code: recovery_code)
          user.update!(mfa_secret: nil, mfa_pending_secret: nil, mfa_pending_expires_at: nil,
            mfa_enabled_at: nil, mfa_last_otp_at: nil, mfa_recovery_digests: [])
          user.auth_sessions.where(revoked_at: nil).update_all(revoked_at: Time.current)
          audit!(user, "security.mfa_disabled")
        end
      end

      private

      def valid_session!(user, session)
        raise InvalidCode unless user.active? && user.email_verified_at.present? && session && session.user_id == user.id
        session.reload.lock!
        raise InvalidCode if session.revoked_at || session.access_expires_at <= Time.current || session.expires_at <= Time.current
      end

      def totp(secret)
        ROTP::TOTP.new(secret, issuer: ISSUER, digits: 6, interval: 30)
      end

      def verify_totp!(secret, code, after:)
        raise InvalidCode unless code.is_a?(String) && code.match?(/\A[0-9]{6}\z/) && secret.present?
        # Drift of one prior step only; no acceptance of future codes, and strictly monotonic replay protection.
        timestamp = totp(secret).verify(code, drift_behind: 30, after: after)
        raise InvalidCode unless timestamp
        timestamp
      end

      def digest(value)
        Digest::SHA256.hexdigest(value)
      end

      def audit!(user, action)
        AuditLog.create!(user: user, subject_id: user.id, action: action)
      end
    end
  end
end
