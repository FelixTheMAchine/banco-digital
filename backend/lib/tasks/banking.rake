namespace :banking do
  desc "Reconcilia os saldos com o livro-razão sem alterar lançamentos ou valores"
  task reconcile: :environment do
    result = Banking::Reconciliation.call
    puts JSON.generate(result)
    abort "Foram encontradas divergências; contas afetadas bloqueadas para revisão" unless result[:reconciled]
  end

  desc "Reenvia agendamentos vencidos para a fila; o scheduler faz isso automaticamente"
  task dispatch_scheduled: :environment do
    puts "Agendamentos enviados: #{Banking::Scheduling.dispatch_due!}"
  end
end
