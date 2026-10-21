class RequestLimits
  MAX_BYTES = 32_768

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless env["PATH_INFO"].start_with?("/api/")

    if env["CONTENT_LENGTH"].to_i > MAX_BYTES
      return error(413, "payload_too_large", "Requisição muito grande.")
    end
    input = env["rack.input"]
    body = input&.read(MAX_BYTES + 1) || ""
    input&.rewind
    return error(413, "payload_too_large", "Requisição muito grande.") if body.bytesize > MAX_BYTES

    if %w[POST PATCH].include?(env["REQUEST_METHOD"]) || !body.empty?
      return error(415, "unsupported_media_type", "Envie JSON.") unless env["CONTENT_TYPE"].to_s.split(";").first == "application/json"
      unless body.empty?
        begin
          return error(400, "invalid_json", "Envie um objeto JSON válido.") unless JSON.parse(body).is_a?(Hash)
        rescue JSON::ParserError, JSON::NestingError
          # Reject before Rails parses/logs malformed bodies containing credentials.
          return error(400, "invalid_json", "Envie um objeto JSON válido.")
        end
      end
    end
    @app.call(env)
  end

  private

  def error(status, code, message)
    [status, { "content-type" => "application/json", "cache-control" => "no-store" },
     [JSON.generate(error: { code: code, message: message })]]
  end
end
