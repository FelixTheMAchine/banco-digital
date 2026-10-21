namespace :admin do
  desc "Promove um cliente verificado com MFA, por confirmação interativa local"
  task create: :environment do
    abort "Execute em terminal interativo; não forneça credenciais por argumentos." unless STDIN.tty?
    print "E-mail do cliente de demonstração já verificado: "
    email = STDIN.gets&.strip&.downcase
    user = User.find_by(email: email)
    abort "É necessário um cliente ativo, verificado e com MFA habilitado." unless user&.active? && user.email_verified_at && user.mfa_enabled?
    print "Digite PROMOVER para confirmar o papel administrativo: "
    abort "Operação cancelada." unless STDIN.gets&.strip == "PROMOVER"
    user.with_lock do
      abort "O cliente precisa continuar ativo, verificado e com MFA habilitado." unless user.active? && user.email_verified_at && user.mfa_enabled?
      user.update!(role: "admin")
      user.auth_sessions.where(revoked_at: nil).update_all(revoked_at: Time.current)
      AuditLog.create!(user: user, subject_id: user.id, action: "admin.provisioned_locally")
    end
    puts "Papel administrativo atribuído. Entre novamente usando senha e MFA."
  end
end
