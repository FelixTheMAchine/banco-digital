require "securerandom"

module Banking
  class Scheduler
    def self.tick!
      redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"), connect_timeout: 2, read_timeout: 2)
      return 0 unless redis.set("banco:scheduling:lease", SecureRandom.hex(16), nx: true, ex: 20)

      Scheduling.dispatch_due!
    ensure
      redis&.close
    end

    def self.run!
      loop do
        begin
          tick!
        rescue StandardError => error
          Rails.logger.error("scheduler_failed class=#{error.class.name}")
        end
        sleep 30
      end
    end
  end
end
