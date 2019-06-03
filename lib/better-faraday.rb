# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "faraday"
require "faraday/error"
require "faraday/options"
require "faraday/response"
require "active_support/core_ext/object/deep_dup"
require "active_support/core_ext/string/filters"
require "active_support/core_ext/string/inflections"

Module.new do
  def run_request(method, url, body, headers, &block)
    super.tap { |response| response.env.instance_variable_set(:@request_body, body) }
  end
end.tap { |m| Faraday::Connection.send(:prepend, m) }

module Faraday
  class Env
    attr_reader :request_body
  end

  class Error
    attr_reader :response

    def inspect
      super.gsub(/\s*\(\s*\)\s*\z/, "")
    end
  end

  class Response
    def assert_2xx!
      return self if status >= 200 && status <= 299

      klass = if status >= 400 && status <= 499
        "Faraday::HTTP#{status}".safe_constantize || Faraday::HTTP4xx
      else
        Faraday::Error
      end

      error = klass.new(describe)
      error.instance_variable_set(:@response, self)
      raise error
    end

    alias ok! assert_2xx! # Short name.
    alias assert_success! assert_2xx! # Compatibility.

    def describe
      request_headers  = env.request_headers.deep_dup
      request_json     = parse_json(env.request_body)
      response_headers = ::Hash === env.response_headers ? env.response_headers.deep_dup : {}
      response_json    = parse_json(env.body)
      [request_headers, request_json, response_headers, response_json].compact.each(&method(:protect!))

      [ "",
        "-- #{status} #{reason_phrase} --",
        "",
        "-- Request URL --",
        env.url.to_s,
        "",
        "-- Request method --",
        env.method.to_s.upcase,
        "",
        "-- Request headers --",
        ::JSON.generate(request_headers).yield_self { |t| t.truncate(1024, omission: "... (truncated, full length: #{t.length})") },
        "",
        "-- Request body --",
        (request_json ? ::JSON.generate(request_json) : env.request_body.to_s).yield_self { |t| t.truncate(1024, omission: "... (truncated, full length: #{t.length})") },
        "",
        "-- Response headers --",
        (response_headers ? ::JSON.generate(response_headers) : env.response_headers.to_s).yield_self { |t| t.truncate(1024, omission: "... (truncated, full length: #{t.length})") },
        "",
        "-- Response body --",
        (response_json ? ::JSON.generate(response_json) : env.body.to_s).yield_self { |t| t.truncate(1024, omission: "... (truncated, full length: #{t.length})") },
        ""
      ].join("\n")
    end

  private

    def parse_json(json)
      data = ::JSON.parse(::String === json ? json : json.to_s)
      data if ::Hash === data || ::Array === data
    rescue ::JSON::ParserError
      nil
    end

    def protect!(x)
      return x.map!(&method(:protect!)) if ::Array === x
      x.keys.each do |k|
        x[k] = "SECRET" if k.respond_to?(:=~) && Faraday.secrets.any? { |s| k =~ s }
        protect!(x[k]) if ::Hash === x[k]
      end
    end
  end

  class HTTP4xx < Error; end
  class HTTP400 < HTTP4xx; end
  class HTTP401 < HTTP4xx; end
  class HTTP403 < HTTP4xx; end
  class HTTP404 < HTTP4xx; end
  class HTTP422 < HTTP4xx; end
  class HTTP429 < HTTP4xx; end

  class << self
    attr_accessor :secrets
  end

  self.secrets = [/\bpass(?:word|phrase)\b/i, /\bauthorization\b/i, /\bsecret\b/i, /\b(:?access?)token\b/i]
end
