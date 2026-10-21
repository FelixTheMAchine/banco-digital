class AuthenticationMailer < ApplicationMailer
  def verification
    @user = params.fetch(:user)
    @token = params.fetch(:token)
    @url = "#{ENV.fetch('APP_FRONTEND_URL', 'http://localhost:3000')}/verificar-email?token=#{@token}"
    mail(to: @user.email, subject: "Confirme seu e-mail — Banco Digital Simulado")
  end

  def password_reset
    @user = params.fetch(:user)
    @token = params.fetch(:token)
    @url = "#{ENV.fetch('APP_FRONTEND_URL', 'http://localhost:3000')}/redefinir-senha?token=#{@token}"
    mail(to: @user.email, subject: "Redefinição de senha — Banco Digital Simulado")
  end
end
