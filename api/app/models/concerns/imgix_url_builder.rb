# frozen_string_literal: true

require "nanoid"

module ImgixUrlBuilder
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

  # Returns avatar URL (Imgix or local fallback)
  def fallback_avatar(name = "", append_params = {})
    color = FALLBACK_AVATAR_COLORS[name.each_byte.sum % FALLBACK_AVATAR_COLORS.length]
    build_imgix_url("static/avatars/#{name[0] ? name[0].upcase : "blank"}.png", append_params.merge("blend-color": color))
  end

  # Returns image URL
  def build_imgix_url(path, append_params = {})
    return local_url(path) if ENV['DISABLE_CDN'] == 'true'

    uri = Addressable::URI.parse(Rails.application.credentials.imgix&.url)
    uri.path = path
    uri.query_values = append_params.compact.merge(uri.query_values || {}) if append_params.present?
    uri.to_s
  end

  # Returns folder URL
  def build_imgix_folder_url(path, append_params = {})
    return local_url(path) if ENV['DISABLE_CDN'] == 'true'

    uri = Addressable::URI.parse(Rails.application.credentials.imgix_folder.url)
    uri.path = path
    uri.query_values = append_params.compact.merge(uri.query_values || {}) if append_params.present?
    uri.to_s
  end

  # Returns video URL
  def build_imgix_video_url(path, append_params = {})
    return local_url(path) if ENV['DISABLE_CDN'] == 'true'

    uri = Addressable::URI.parse(Rails.application.credentials.imgix_video.url)
    uri.path = path
    uri.query_values = append_params.compact.merge(uri.query_values || {}) if append_params.present?
    uri.to_s
  end

  private

  # Helper to return a local path instead of Imgix
  def local_url(path)
    "/#{path}"
  end
end
