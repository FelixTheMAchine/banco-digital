class AuthenticationInstructionsJob < ApplicationJob
  queue_as :default

  def perform(email:, purpose:)
    raise ArgumentError, "Finalidade inválida" unless %w[email_verification password_reset].include?(purpose)

    user = User.find_by(email: email)
    return unless user&.active?
    return if purpose == "email_verification" && user.email_verified_at.present?
    return if purpose == "password_reset" && user.email_verified_at.nil?

    token = Auth::PurposeTokenService.issue!(user: user, purpose: purpose)
    mailer = AuthenticationMailer.with(user: user, token: token)
    if purpose == "email_verification"
      mailer.verification.deliver_now
    else
      mailer.password_reset.deliver_now
    end
  rescue Auth::PurposeTokenService::InvalidToken
    # Account deactivation may race this asynchronous, non-enumerating request.
    nil
  end
end
