require "rails_helper"

RSpec.describe Security::MfaService do
  include ActiveSupport::Testing::TimeHelpers
  let(:password) { "Ficticia-Forte-9347!" }

  def session_for(user)
    Auth::SessionService.issue!(user: user, mfa_verified_at: (Time.current if user.mfa_enabled?))
    user.auth_sessions.order(:created_at).last
  end

  it "encrypts a pending secret at rest and requires the current password" do
    user = create_user
    expect { described_class.start_enrollment!(user: user, session: session_for(user), password: "wrong-password") }.to raise_error(described_class::InvalidCode)
    response = described_class.start_enrollment!(user: user, session: session_for(user), password: password)
    expect(response.fetch(:provisioning_uri)).to start_with("otpauth://totp/")
    expect(user.reload.mfa_pending_secret).to eq(response.fetch(:secret))
    ciphertext = user.read_attribute_before_type_cast(:mfa_pending_secret)
    expect(ciphertext).not_to include(response.fetch(:secret))
  end

  it "enables MFA with hashed recovery codes and rejects OTP replay" do
    travel_to Time.utc(2026, 1, 1, 12, 0, 5) do
      user = create_user
      session = session_for(user)
      enrollment = described_class.start_enrollment!(user: user, session: session_for(user), password: password)
      code = ROTP::TOTP.new(enrollment.fetch(:secret)).now
      codes = described_class.enable!(user: user, session: session, code: code)
      expect(codes.size).to eq(8)
      expect(user.reload.mfa_enabled?).to be(true)
      expect(user.mfa_recovery_digests).not_to include(*codes)
      expect(session.reload.mfa_verified_at).to be_present
      expect { described_class.verify!(user: user, code: code) }.to raise_error(described_class::InvalidCode)
      travel 30.seconds
      expect(described_class.verify!(user: user, code: ROTP::TOTP.new(enrollment.fetch(:secret)).now)).to be(true)
    end
  end

  it "expires incomplete enrollments" do
    user = create_user
    session = session_for(user)
    enrollment = described_class.start_enrollment!(user: user, session: session_for(user), password: password)
    user.update!(mfa_pending_expires_at: 1.second.ago)
    expect do
      described_class.enable!(user: user, session: session, code: ROTP::TOTP.new(enrollment.fetch(:secret)).now)
    end.to raise_error(described_class::InvalidCode)
    expect(user.reload.mfa_enabled?).to be(false)
  end

  it "accepts each recovery credential once" do
    user = create_user
    session = session_for(user)
    enrollment = described_class.start_enrollment!(user: user, session: session_for(user), password: password)
    codes = described_class.enable!(user: user, session: session, code: ROTP::TOTP.new(enrollment.fetch(:secret)).now)
    expect(described_class.verify!(user: user, recovery_code: codes.first)).to be(true)
    expect(user.reload.mfa_recovery_digests.size).to eq(7)
    expect { described_class.verify!(user: user, recovery_code: codes.first) }.to raise_error(described_class::InvalidCode)
  end

  it "revokes other sessions when MFA becomes enabled" do
    user = create_user
    first = session_for(user)
    second = session_for(user)
    enrollment = described_class.start_enrollment!(user: user, session: session_for(user), password: password)
    described_class.enable!(user: user, session: first, code: ROTP::TOTP.new(enrollment.fetch(:secret)).now)
    expect(first.reload.revoked_at).to be_nil
    expect(second.reload.revoked_at).to be_present
  end
  it "does not change MFA state from a revoked session" do
    user = create_user
    session = session_for(user)
    enrollment = described_class.start_enrollment!(user: user, session: session, password: password)
    session.update!(revoked_at: Time.current)
    expect do
      described_class.enable!(user: user, session: session, code: ROTP::TOTP.new(enrollment.fetch(:secret)).now)
    end.to raise_error(described_class::InvalidCode)
    expect(user.reload.mfa_enabled?).to be(false)
    expect(session.reload.revoked_at).to be_present
  end

  it "requires a live session for step-up and never revives a revoked token" do
    secret = ROTP::Base32.random_base32
    user = create_user(mfa_secret: secret, mfa_enabled_at: Time.current)
    session = session_for(user)
    session.update!(revoked_at: Time.current)
    expect do
      described_class.step_up!(user: user, session: session, code: ROTP::TOTP.new(secret).now)
    end.to raise_error(described_class::InvalidCode)
    expect(session.reload.revoked_at).to be_present
    expect(user.reload.mfa_last_otp_at).to be_nil
  end

  it "allows a customer to disable MFA only with password and an unused second factor" do
    user = create_user
    session = session_for(user)
    enrollment = described_class.start_enrollment!(user: user, session: session, password: password)
    codes = described_class.enable!(user: user, session: session, code: ROTP::TOTP.new(enrollment.fetch(:secret)).now)
    described_class.disable!(user: user, session: session, password: password, recovery_code: codes.first)
    expect(user.reload.mfa_enabled?).to be(false)
    expect(user.mfa_secret).to be_nil
    expect(user.auth_sessions.where(revoked_at: nil)).not_to exist
  end

  it "does not allow an administrator to downgrade to password-only authentication" do
    secret = ROTP::Base32.random_base32
    user = create_user(role: "admin", mfa_secret: secret, mfa_enabled_at: Time.current)
    session = session_for(user)
    expect do
      described_class.disable!(user: user, session: session, password: password, code: ROTP::TOTP.new(secret).now)
    end.to raise_error(described_class::InvalidCode)
    expect(user.reload.mfa_enabled?).to be(true)
    expect(session.reload.revoked_at).to be_nil
  end

end
