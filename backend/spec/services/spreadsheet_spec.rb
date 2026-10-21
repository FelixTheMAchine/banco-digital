require "rails_helper"
require "zip"

RSpec.describe Reports::Spreadsheet do
  it "neutralizes formula prefixes including leading whitespace and control characters" do
    ["=SUM(A1:A2)", "+cmd", "-cmd", "@SUM(A1)", " \t=1+1", "\tvalue", "\rvalue"].each do |text|
      expect(described_class.safe_text(text)).to start_with("'")
    end
    expect(described_class.safe_text("Descrição normal")).to eq("Descrição normal")
  end

  it "creates a bounded XLSX workbook and audits the export without exporting secrets" do
    admin = create_user(role: "admin", mfa_secret: ROTP::Base32.random_base32, mfa_enabled_at: Time.current)
    report = described_class.new(actor: admin, kind: "accounts")
    bytes = report.generate
    expect(bytes.byteslice(0, 2)).to eq("PK")
    xml = Zip::File.open_buffer(bytes) do |archive|
      archive.glob("xl/**/*.xml").map { |entry| entry.get_input_stream { |stream| stream.read } }.join
    end
    expect(xml).not_to include("password_digest", "refresh_digest", admin.password_digest, admin.mfa_secret)
    expect(AuditLog.where(user: admin, action: "admin.export.accounts")).to exist
  end

  it "prevents direct report generation by an ordinary customer" do
    expect { described_class.new(actor: create_user, kind: "accounts") }.to raise_error(ArgumentError)
  end

  it "rejects invalid report types and reversed dates" do
    admin = create_user(role: "admin", mfa_secret: ROTP::Base32.random_base32, mfa_enabled_at: Time.current)
    expect { described_class.new(actor: admin, kind: "passwords") }.to raise_error(ArgumentError)
    expect { described_class.new(actor: admin, kind: "accounts", from: "2026-02-02", to: "2026-01-01") }.to raise_error(ArgumentError)
  end
end
