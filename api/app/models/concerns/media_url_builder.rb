# frozen_string_literal: true

require "nanoid"

module MediaUrlBuilder
  extend ActiveSupport::Concern

  FALLBACK_AVATAR_COLORS = [
    "3b82f6", # blue.500
    "4ade80", # green.400
    "fde047", # yellow.300
    "ef4444", # red.500
    "9333ea", # purple.300
    "ec4899", # pink.500
    "6366f1", # indigo.500
    "5eead4", # teal.300
  ].freeze

  # Parameter mapping from Imgix to Cloudflare Image Resizing
  IMGIX_TO_CLOUDFLARE_PARAMS = {
    "w" => "width",
    "h" => "height",
    "q" => "quality",
    "fit" => "fit",           # May need value mapping
    "dpr" => "dpr",
    "auto" => "format",       # Needs value transformation
    "fm" => "format",
    "dl" => "download",
    "frame" => "frame",
    "blend-color" => "blend", # May need adjustment
  }.freeze

  # Value mapping for specific parameters
  IMGIX_FIT_TO_CLOUDFLARE = {
    "crop" => "cover",
    "clip" => "scale-down",
    "clamp" => "contain",
    "scale" => "contain",
    "max" => "scale-down",
    "min" => "cover",
  }.freeze

  # === Configuration ===
  
  def cdn_provider
    # Check credentials to determine which CDN provider is configured
    @cdn_provider ||= if Rails.application.credentials.dig(:cloudflare, :cdn_url).present?
      :cloudflare
    elsif Rails.application.credentials.dig(:imgix, :url).present?
      :imgix
    else
      :cloudflare # default
    end
  end

  def fallback_avatar(name = "", append_params = {})
    color = FALLBACK_AVATAR_COLORS[name.each_byte.sum % FALLBACK_AVATAR_COLORS.length]
    build_imgix_url(
      "static/avatars/#{name[0] ? name[0].upcase : "blank"}.png",
      append_params.merge("blend-color": color)
    )
  end

  
  # Main URL builder - delegates to appropriate CDN
  def build_imgix_url(path, append_params = {})
    case cdn_provider
    when :imgix
      build_imgix_cdn_url(path, append_params)
    when :cloudflare
      build_cloudflare_cdn_url(path, append_params)
    end
  end

  def build_imgix_folder_url(path, append_params = {})
    case cdn_provider
    when :imgix
      build_imgix_cdn_folder_url(path, append_params)
    when :cloudflare
      build_cloudflare_cdn_url(path, append_params, url_key: :folder_cdn_url)
    end
  end

  def build_imgix_video_url(path, append_params = {})
    case cdn_provider
    when :imgix
      build_imgix_cdn_video_url(path, append_params)
    when :cloudflare
      build_cloudflare_cdn_url(path, append_params, url_key: :video_cdn_url)
    end
  end

  private

  # === Imgix-specific methods ===
  
  def build_imgix_cdn_url(path, append_params = {})
    uri = Addressable::URI.parse(Rails.application.credentials.dig(:imgix, :url))
    uri.path = path
    
    if append_params.present?
      uri.query_values = append_params.compact.merge(uri.query_values || {})
    end
    
    uri.to_s
  end

  def build_imgix_cdn_folder_url(path, append_params = {})
    folder_url = Rails.application.credentials.dig(:imgix_folder, :url)
    folder_url ||= Rails.application.credentials.dig(:imgix, :url)
    
    uri = Addressable::URI.parse(folder_url)
    uri.path = path
    
    if append_params.present?
      uri.query_values = append_params.compact.merge(uri.query_values || {})
    end
    
    uri.to_s
  end

  def build_imgix_cdn_video_url(path, append_params = {})
    video_url = Rails.application.credentials.dig(:imgix_video, :url)
    video_url ||= Rails.application.credentials.dig(:imgix, :url)
    
    uri = Addressable::URI.parse(video_url)
    uri.path = path
    
    if append_params.present?
      uri.query_values = append_params.compact.merge(uri.query_values || {})
    end
    
    uri.to_s
  end

  # === Cloudflare-specific methods ===
  
  def build_cloudflare_cdn_url(path, append_params = {}, url_key: :cdn_url)
    cdn_url = Rails.application.credentials.dig(:cloudflare, url_key)
    # Fallback to main cdn_url if specific URL is not configured
    cdn_url ||= Rails.application.credentials.dig(:cloudflare, :cdn_url)
    
    uri = Addressable::URI.parse(cdn_url)
    uri.path = "/cdn/#{path}"
    
    if append_params.present?
      # Transform Imgix parameters to Cloudflare format
      cloudflare_params = transform_imgix_to_cloudflare_params(append_params)
      uri.query_values = cloudflare_params.compact.merge(uri.query_values || {})
    end
    
    uri.to_s
  end

  def transform_imgix_to_cloudflare_params(imgix_params)
    cloudflare_params = {}
    
    imgix_params.each do |key, value|
      key_str = key.to_s
      
      # Map parameter names
      cf_key = IMGIX_TO_CLOUDFLARE_PARAMS[key_str] || key_str
      
      # Transform specific values
      cf_value = case key_str
      when "fit"
        IMGIX_FIT_TO_CLOUDFLARE[value.to_s] || value
      when "auto"
        # Imgix "auto=compress,format" -> Cloudflare "format=auto"
        value.to_s.include?("format") ? "auto" : value
      when "blend-color"
        # Cloudflare may not support blend-color, keep for now
        value
      else
        value
      end
      
      cloudflare_params[cf_key] = cf_value
    end
    
    cloudflare_params
  end
end
