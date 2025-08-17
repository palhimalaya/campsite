# frozen_string_literal: true

ActiveSupport::Notifications.subscribe("request.action_dispatch") do |_name, start, _finish, _id, payload|
  request_start_header_value = payload[:request].headers["X-Request-Start"]
  next unless request_start_header_value

  match_data = request_start_header_value.match(/^t=(?<microseconds>\d+)/)
  next unless match_data

  request_start_microseconds_since_epoch = match_data[:microseconds].to_i
  next if request_start_microseconds_since_epoch.zero?

  request_start_time = Time.zone.at(request_start_microseconds_since_epoch / 1_000_000.0)
  request_queue_time = start - request_start_time
  Rails.logger.info("queue_time=#{request_queue_time.in_milliseconds.to_i}ms")
end
