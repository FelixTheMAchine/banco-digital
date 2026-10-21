class RateLimitAvailability
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue Redis::BaseError, RedisClient::Error
    # A missing rate limiter must never permit a sensitive request to proceed.
    [503, { "content-type" => "application/json", "cache-control" => "no-store", "retry-after" => "30",
            "x-content-type-options" => "nosniff" },
     [JSON.generate(error: { code: "service_unavailable", message: "Serviço temporariamente indisponível. Tente novamente." })]]
  end
end
