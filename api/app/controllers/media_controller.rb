# frozen_string_literal: true

class MediaController < ApplicationController
  # Public: Proxy GET /media/*path to the protected S3 bucket (S3_BUCKET)
  # This endpoint is intended to be the origin for the CDN (Cloudflare).
  
  # Skip authentication - CDN will call this publicly. If you want to restrict
  # it to Cloudflare IPs, add a middleware or IP constraint.
  skip_before_action :require_authenticated_user, raise: false

  def show
    path = params[:path]
    return head :bad_request if path.blank?

    begin
      Rails.logger.info "[MediaController] incoming media request"
      Rails.logger.info "  host=#{request.host} forwarded_host=#{request.headers['X-Forwarded-Host']} cf_connecting_ip=#{request.headers['CF-Connecting-IP']} path=#{path}"
      Rails.logger.debug "  headers=#{request.headers.env.select { |k, _| k.start_with?('HTTP_') }.inspect}"

      object = S3_BUCKET.object(path)

      # Check existence and permissions
      unless object.exists?
        Rails.logger.warn "[MediaController] S3 object not found: #{path}"
        return head :not_found
      end

      # Stream the object body
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      resp = object.get
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(1)
      Rails.logger.info "[MediaController] fetched S3 object=#{path} time_ms=#{duration_ms} size=#{resp.content_length || 'unknown'}"

      # Set caching headers to encourage CDN caching
      response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
      response.headers["ETag"] = resp.etag if resp.etag
      response.headers["Last-Modified"] = resp.last_modified.httpdate if resp.last_modified
      response.headers["Access-Control-Allow-Origin"] = "*"
      response.headers["X-Proxy-Source"] = "s3"

      send_data resp.body.read, type: resp.content_type || "application/octet-stream", disposition: "inline"
    rescue Aws::S3::Errors::Forbidden
      Rails.logger.warn "[MediaController] S3 forbidden for #{path}: #{e.class}: #{e.message}" rescue nil
      head :forbidden
    rescue Aws::S3::Errors::NoSuchKey
      Rails.logger.warn "[MediaController] S3 no such key #{path}" rescue nil
      head :not_found
    rescue StandardError => e
      Rails.logger.error "[MediaController] Error proxying S3 object #{path}: #{e.class}: #{e.message}\n#{e.backtrace&.take(10)&.join("\n")}" 
      # Add a header so Cloudflare / clients can surface the proxy error class
      response.headers["X-Proxy-Error"] = e.class.to_s
      head :internal_server_error
    end
  end
end
