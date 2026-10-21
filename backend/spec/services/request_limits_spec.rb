require "rails_helper"
require "stringio"

RSpec.describe RequestLimits do
  it "rejects a chunked DELETE beyond the limit even without Content-Length" do
    downstream_called = false
    app = described_class.new(->(_env) { downstream_called = true; [200, {}, ["ok"]] })
    env = {
      "PATH_INFO" => "/api/v1/security/mfa", "REQUEST_METHOD" => "DELETE",
      "CONTENT_TYPE" => "application/json", "HTTP_TRANSFER_ENCODING" => "chunked",
      "rack.input" => StringIO.new(JSON.generate(password: "a" * 40_000))
    }
    status, _headers, body = app.call(env)
    expect(status).to eq(413)
    expect(downstream_called).to be(false)
    expect(body.join).not_to include("a" * 100)
  end
end
