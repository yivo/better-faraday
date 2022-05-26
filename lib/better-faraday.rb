# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "net/http"
require "faraday"
require "faraday/error"
require "faraday/options"
require "faraday/response"
require "active_support/core_ext/object/deep_dup"
require "active_support/core_ext/string/filters"
require "active_support/core_ext/string/inflections"
require "active_support/core_ext/object/inclusion"

Module.new do
  def call(environment)
    environment.instance_variable_set(:@bf_request_sent_at, Time.now.utc)
    super
  end

  def save_response(environment, *)
    environment.instance_variable_set \
      :@bf_response_received_at,
      Time.now.utc

    body = environment.body
    value = body.respond_to?(:read) ? body.read : body
    value = value.to_s unless String === value

    environment.instance_variable_set \
      :@bf_request_body,
      value

    super
  end
end.tap { |m| Faraday::Adapter.prepend(m) }

Module.new do
  def end_transport(request, response)
    headers = request.to_hash
    headers.keys.each { |k| headers[k] = headers[k].join(", ") }
    response.instance_variable_set :@bf_request_headers, headers
    super
  end
end.tap { |m| Net::HTTP.prepend(m) }

Module.new do
  def perform_request(connection, environment)
    super(connection, environment).tap do |response|
      environment.instance_variable_set \
        :@bf_request_headers,
        response.instance_variable_get(:@bf_request_headers)
    end
  end
end.tap { |m| Faraday::Adapter::NetHttp.prepend(m) }

module Faraday
  class Env
    attr_reader :bf_request_headers, :bf_request_body, :bf_request_sent_at, :bf_response_received_at
  end

  class Response
    def assert_status!(code_or_range)
      within_range = if Range === code_or_range
        status.in?(code_or_range)
      else
        status == code_or_range
      end

      return self if within_range

      klass = if status_4xx?
        "BetterFaraday::HTTP#{status}".safe_constantize || BetterFaraday::HTTP4xx
      elsif status_5xx?
        "BetterFaraday::HTTP#{status}".safe_constantize || BetterFaraday::HTTP5xx
      else
        BetterFaraday::HTTPError
      end

      raise klass.new(self)
    end

    def assert_2xx!
      assert_status!(200..299)
    end

    def assert_200!
      assert_status! 200
    end

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

    def inspect
      @inspection_text ||= begin
        request_headers = bf_protect_data(env.bf_request_headers.dup)
        request_body = env.bf_request_body.yield_self { |body| String === body ? body : body.to_s }
        request_body_bytes_count = env.bf_request_body.bytesize
        response_body = env.body.yield_self { |body| String === body ? body : body.to_s }
        response_body_bytes_count = response_body.bytesize

        if env.bf_request_headers["content-type"].to_s.match?(/\bapplication\/json\b/i)
          request_json = bf_json_parse(request_body).yield_self do |data|
            bf_json_dump(bf_protect_data(data)) if data
          end
        end

        if env.response_headers
          response_headers = bf_protect_data(env.response_headers.to_hash)
        end

        if env.response_headers && env.response_headers["content-type"].to_s.match?(/\bapplication\/json\b/i)
          response_json = bf_json_parse(response_body).yield_self do |data|
            bf_json_dump(bf_protect_data(data)) if data
          end
        end

        lines = [
          "-- #{status} #{reason_phrase} --".upcase,
          "",
          "-- Request URL --",
          env.url.to_s,
          "",
          "-- Request Method --",
          env.method.to_s.upcase,
          "",
          "-- Request Headers --",
          bf_json_dump(request_headers).truncate(2048, omission: "... (truncated)"),
          "",

          %[-- Request Body (#{request_body_bytes_count} #{"byte".pluralize(request_body_bytes_count)}) --],
          if request_json
            request_json
          else
            # String#inspect returns \x{XXXX} for the encoding other than Unicode.
            # [1..-2] removed leading and trailing " added by String#inspect.
            # gsub(/\\"/, "\"") unescapes ".
            request_body.inspect.gsub(/\\"/, "\"")[1..-2]
          end.truncate(2048, omission: "... (truncated)"),
          "",

          "-- Request Sent At --",
          env.bf_request_sent_at.strftime("%Y-%m-%d %H:%M:%S.%3N") + " UTC",
          "",

          "-- Response Headers --",
          if response_headers
            bf_json_dump(response_headers)
          else
            env.response_headers.to_s.inspect.gsub(/\\"/, "\"")[1..-2]
          end.truncate(2048, omission: "... (truncated)"),
          "",

          %[-- Response Body (#{response_body_bytes_count} #{"byte".pluralize(response_body_bytes_count)}) --],
          if response_json
            response_json
          else
            response_body.inspect.gsub(/\\"/, "\"")[1..-2]
          end.truncate(2048, omission: "... (truncated)"),
          ""
        ]

        if env.bf_response_received_at
          lines.concat [
            "-- Response Received At --",
            env.bf_response_received_at.strftime("%Y-%m-%d %H:%M:%S.%3N") + " UTC",
            "",
            "-- Response Received In --",
            "#{((env.bf_response_received_at.to_f - env.bf_request_sent_at.to_f) * 1000.0).ceil(3)}ms",
            ""
          ]
        end

        lines.join("\n").freeze
      end

      @inspection_text.dup
    end

  private

    def bf_json_parse(json)
      return nil unless ::String === json
      data = ::JSON.parse(json)
      data if ::Hash === data || ::Array === data
    rescue ::JSON::ParserError
      nil
    end

    def bf_json_dump(data)
      ::JSON.generate(data, space: " ", object_nl: " ", array_nl: " ")
    end

    def bf_protect_data(data)
      return data.map(&method(:bf_protect_data)) if ::Array === data
      return data unless ::Hash === data

      signs = BetterFaraday.sensitive_data_signs

      data.each_with_object({}) do |(key, value), memo|
        memo[key] = if key.to_s.underscore.tr("_", " ").yield_self { |k| signs.any? { |r| k.match?(r) } }
          "SECRET"
        else
          bf_protect_data(value)
        end
      end
    end
  end
end

module BetterFaraday
  class HTTPError < Faraday::Error
    def initialize(response)
      super(response.inspect, response)
    end

    def inspect
      %[#{self.class}\n\n#{response.inspect}]
    end
  end

  class HTTP4xx < HTTPError; end
  class HTTP400 < HTTP4xx; end
  class HTTP401 < HTTP4xx; end
  class HTTP403 < HTTP4xx; end
  class HTTP404 < HTTP4xx; end
  class HTTP422 < HTTP4xx; end
  class HTTP429 < HTTP4xx; end
  class HTTP5xx < HTTPError; end
  class HTTP500 < HTTP5xx; end
  class HTTP502 < HTTP5xx; end
  class HTTP503 < HTTP5xx; end

  class << self
    attr_accessor :sensitive_data_signs
  end

  self.sensitive_data_signs = [
    /\bpass(?:word|phrase)\b/i,
    /\bauthorization\b/i,
    /\bsecret\b/i,
    /\b(:?access)?token\b/i
  ]
end
