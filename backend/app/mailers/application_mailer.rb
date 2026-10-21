class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "nao-responda@banco-digital.example")
  layout false
end
