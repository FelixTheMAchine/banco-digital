class ReconciliationJob < ApplicationJob
  queue_as :default

  def perform
    Banking::Reconciliation.call
  end
end
