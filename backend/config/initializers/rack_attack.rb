class Rack::Attack
  self.cache.store = if Rails.env.test?
    ActiveSupport::Cache::MemoryStore.new
  else
    ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
      namespace: "banco:limits", error_handler: ->(method:, returning:, exception:) { raise exception })
  end

  throttle("api/ip", limit: 120, period: 1.minute) do |request|
    request.ip if request.path.start_with?("/api/") && request.path != "/api/v1/health"
  end
  throttle("auth/ip", limit: 10, period: 1.minute) do |request|
    request.ip if request.path.start_with?("/api/v1/auth/")
  end
  throttle("mfa/ip", limit: 10, period: 5.minutes) do |request|
    request.ip if request.path.start_with?("/api/v1/security/mfa")
  end
  throttle("mfa/session", limit: 10, period: 5.minutes) do |request|
    if request.path.start_with?("/api/v1/security/mfa")
      bearer = request.get_header("HTTP_AUTHORIZATION").to_s
      Digest::SHA256.hexdigest(bearer) unless bearer.empty?
    end
  end
  # Login uses path + normalized identifier digest; raw e-mails never become Redis keys.
  throttle("login/identity", limit: 5, period: 5.minutes) do |request|
    if request.post? && request.path == "/api/v1/auth/login"
      begin
        input = JSON.parse(request.body.read(32_769) || "")
        request.body.rewind
        email = input["email"] if input.is_a?(Hash)
        Digest::SHA256.hexdigest(email.strip.downcase) if email.is_a?(String)
      rescue JSON::ParserError
        request.body.rewind
        nil
      end
    end
  end
  self.throttled_responder = lambda do |request|
    retry_after = request.env.fetch("rack.attack.match_data", {}).fetch(:period, 60).to_i
    [429, { "content-type" => "application/json", "retry-after" => retry_after.to_s, "cache-control" => "no-store" },
     [JSON.generate(error: { code: "rate_limited", message: "Muitas tentativas. Tente novamente mais tarde." })]]
  end
end
Rails.application.config.middleware.use Rack::Attack
