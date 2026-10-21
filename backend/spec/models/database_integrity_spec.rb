require "rails_helper"

RSpec.describe "PostgreSQL integrity boundaries", type: :model do
  it "enforces email uniqueness even when application validation is bypassed" do
    first = create_user
    second = create_user
    expect do
      User.transaction(requires_new: true) { second.update_columns(email: first.email) }
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect(second.reload.email).not_to eq(first.email)
  end

  it "prevents negative monetary declarations at the database boundary" do
    user = create_user
    expect do
      User.transaction(requires_new: true) { user.update_columns(monthly_salary_cents: -1) }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(user.reload.monthly_salary_cents).to eq(600_000)
  end

  it "protects audit evidence from direct SQL updates and deletions" do
    user = create_user
    audit = AuditLog.create!(user: user, action: "spec.audit", subject_id: user.id)
    expect do
      AuditLog.transaction(requires_new: true) { AuditLog.where(id: audit.id).update_all(action: "rewritten") }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect do
      AuditLog.transaction(requires_new: true) { AuditLog.where(id: audit.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(audit.reload.action).to eq("spec.audit")
  end
end
