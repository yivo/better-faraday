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
  def call(env)
    env.instance_variable_set(:@request_sent_at, Time.now.utc)
    super
  end

  def save_response(env, status, body, headers = nil, reason_phrase = nil)
    env.instance_variable_set(:@response_received_at, Time.now.utc)
    env.instance_variable_set(:@request_body, env.body.respond_to?(:read) ? env.body.read : env.body)
    super
  end
end.tap { |m| Faraday::Adapter.send(:prepend, m) }

module Faraday
  class Env
    attr_reader :request_body, :request_sent_at, :response_received_at
  end

  class Error
    attr_reader :response

    def inspect
      super.gsub(/\s*\(\s*\)\s*\z/, "")
    end
  end

  class Response
    def assert_2xx!
      return self if status_2xx?

      klass = if status_4xx?
        "Faraday::HTTP#{status}".safe_constantize || Faraday::HTTP4xx
      else
        Faraday::Error
      end

      error = klass.new("\n#{describe}")
      error.instance_variable_set(:@response, self)
      raise error
    end

    alias ok! assert_2xx! # Short name.
    alias assert_success! assert_2xx! # Compatibility.

    def status_2xx?
      status >= 200 && status <= 299
    end

    def status_3xx?
      status >= 300 && status <= 399
    end

    def status_4xx?
      status >= 400 && status <= 499
    end

    def status_5xx?
      status >= 500 && status <= 599
    end

    def describe
      request_headers = __protect_data(env.request_headers.deep_dup)

      if env.request_headers["Content-Type"].to_s.match?(/\bapplication\/json\b/)
        request_json = __protect_data(__parse_json(env.request_body.dup))
      end

      if env.response_headers
        response_headers = __protect_data(env.response_headers.deep_dup)
      end

      if env.response_headers && env.response_headers["Content-Type"].to_s.match?(/\bapplication\/json\b/)
        response_json = __protect_data(__parse_json(env.body.dup))
      end

      lines = [
        "",
        "-- #{status} #{reason_phrase} --".upcase,
        "",
        "-- Request URL --",
        env.url.to_s,
        "",
        "-- Request method --",
        env.method.to_s.upcase,
        "",
        "-- Request headers --",
        ::JSON.generate(request_headers).yield_self { |t| t.truncate(2048, omission: "... (truncated, full length: #{t.length})") },
        "",

        "-- Request body --",
        if request_json
          ::JSON.generate(request_json)
        else
          body = env.request_body.to_s.dup
          if body.encoding.name == "ASCII-8BIT"
            "Binary (#{body.size} bytes)"
          else
            body
          end
        end.yield_self { |t| t.truncate(1024, omission: "... (truncated, full length: #{t.length})") },
        "",

        "-- Request sent at --",
        env.request_sent_at.strftime("%Y-%m-%d %H:%M:%S.%2N") + " UTC",
        "",

        "-- Response headers --",
        if response_headers
          ::JSON.generate(response_headers)
        else
          env.response_headers.to_s
        end.yield_self { |t| t.truncate(2048, omission: "... (truncated, full length: #{t.length})") },
        "",

        "-- Response body --",
        if response_json
          ::JSON.generate(response_json)
        else
          body = env.body.to_s.dup
          if body.encoding.name == "ASCII-8BIT"
            "Binary (#{body.size} bytes)"
          else
            body
          end
        end.yield_self { |t| t.truncate(2048, omission: "... (truncated, full length: #{t.length})") }
      ]

      if env.response_received_at
        lines.concat [
          "",
          "-- Response received at --",
          env.response_received_at.strftime("%Y-%m-%d %H:%M:%S.%2N") + " UTC",
          "",
          "-- Response received in --",
          "#{((env.response_received_at.to_f - env.request_sent_at.to_f) * 1000.0).round(2)}ms"
        ]
      end

      lines.join("\n") + "\n"
    end

  private

    def __parse_json(json)
      return nil unless ::String === json
      data = ::JSON.parse(json)
      data if ::Hash === data || ::Array === data
    rescue ::JSON::ParserError
      nil
    end

    def __protect_data(data)
      return data.map(&method(:__protect_data)) if ::Array === data
      return data unless ::Hash === data
      data.each_with_object({}) do |(key, value), memo|
        memo[key] = if key.to_s.underscore.tr("_", " ").yield_self { |k| Faraday.secrets.any? { |s| k.match?(s) } }
          "SECRET"
        else
          __protect_data(value)
        end
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

  self.secrets = [/\bpass(?:word|phrase)\b/i, /\bauthorization\b/i, /\bsecret\b/i, /\b(:?access)?token\b/i]
end
