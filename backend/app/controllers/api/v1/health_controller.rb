module Api
  module V1
    class HealthController < ApplicationController
      def show
        ActiveRecord::Base.connection.select_value("SELECT 1")
        redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0"), connect_timeout: 1, read_timeout: 1)
        raise Redis::BaseError unless redis.ping == "PONG"

        render json: { status: "ok", simulation: true }
      rescue ActiveRecord::ActiveRecordError, Redis::BaseError, RedisClient::Error, SocketError, IOError, SystemCallError
        render_error("service_unavailable", "Serviço temporariamente indisponível.", status: :service_unavailable)
      ensure
        redis&.close
      end
    end
  end
end
