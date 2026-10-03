# frozen_string_literal: true

require "json"
require "net/http"
require "faraday"
require "faraday/error"
require "faraday/options"
require "faraday/response"
require "logger"

# Faraday::Adapter middleware extension
Module.new do
  def call(*args, **kwargs, &block)
    environment = args.first

    unless environment.nil?
      BetterFaraday.set_value \
        environment,
        "environment",
        "bf_request_sent_at",
        Time.now.utc,
        "Faraday::Adapter#call"

      # Eagerly capture headers as a fallback BEFORE the adapter executes.
      # If the adapter is a real network adapter (like Net::HTTP), it will overwrite
      # these with the exact wire headers later. Test adapters will use this fallback.
      BetterFaraday.set_value \
        environment,
        "environment",
        "bf_request_headers",
        environment.request_headers,
        "Faraday::Adapter#call"
    end

    super
  end

  def save_response(*args, **kwargs, &block)
    environment = args.first

    unless environment.nil?
      BetterFaraday.set_value \
        environment,
        "environment",
        "bf_response_received_at",
        Time.now.utc,
        "Faraday::Adapter#save_response"

      body = environment.body

      # Safely read the body. We MUST rewind BEFORE reading because the
      # HTTP adapter or test stub has likely already consumed the stream to EOF.
      value = if body.respond_to?(:read)
        body.rewind if body.respond_to?(:rewind)
        content = body.read
        body.rewind if body.respond_to?(:rewind) # Rewind again to leave it clean
        content
      else
        body
      end

      BetterFaraday.set_value \
        environment,
        "environment",
        "bf_request_body",
        value.is_a?(String) ? value : value.to_s,
        "Faraday::Adapter#save_response"
    end

    super
  end
end.tap { |m| Faraday::Adapter.prepend(m) }

# Net::HTTP middleware extension
Module.new do
  def end_transport(*args, **kwargs, &block)
    request, response = args[0], args[1]

    if !request.nil? && !response.nil?
      headers = request.to_hash
      headers.each_key { headers[_1] = headers[_1].join(", ") }

      BetterFaraday.set_value \
        response,
        "response",
        "bf_request_headers",
        headers,
        "Net::HTTP#end_transport"
    end

    super
  end
end.tap { |m| Net::HTTP.prepend(m) }

# Faraday::Adapter::NetHttp middleware extension
Module.new do
  def perform_request(*args, **kwargs, &block)
    # Faraday 1.x passes (http, env), Faraday 2.x passes (env)
    environment = args.find { _1.is_a?(Faraday::Env) }

    super.tap do |response|
      if !environment.nil? && !response.nil?
        net_headers = BetterFaraday.get_value \
          response,
          "response",
          "bf_request_headers",
          "Faraday::Adapter::NetHttp#perform_request"

        # Overwrite only if Net::HTTP actually provides network headers
        unless net_headers.nil?
          BetterFaraday.set_value \
            environment,
            "environment",
            "bf_request_headers",
            net_headers,
            "Faraday::Adapter::NetHttp#perform_request"
        end
      end
    end
  end
end.tap do |m|
  Faraday::Adapter::NetHttp.prepend(m)

  # Conditionally prepend for NetHttpPersistent if it is loaded (Faraday 1.x)
  Faraday::Adapter::NetHttpPersistent.prepend(m) if defined?(Faraday::Adapter::NetHttpPersistent)
end

module Faraday
  class Env
    attr_reader :bf_request_headers, :bf_request_body, :bf_request_sent_at, :bf_response_received_at
  end

  class Response
    def assert_status!(code_or_range)
      within_range = if code_or_range.is_a?(Range)
        code_or_range.include?(status)
      else
        status == code_or_range
      end

      return self if within_range

      klass_name = "HTTP#{status}"

      klass = if BetterFaraday.const_defined?(klass_name)
        BetterFaraday.const_get(klass_name)
      elsif status_3xx?
        BetterFaraday::HTTP3xx
      elsif status_4xx?
        BetterFaraday::HTTP4xx
      elsif status_5xx?
        BetterFaraday::HTTP5xx
      else
        BetterFaraday::HTTPError
      end

      raise klass, self
    end

    def assert_2xx!
      assert_status!(200..299)
    end

    def assert_200!
      assert_status!(200)
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
      @inspection = bf_inspect if @inspection.nil?
      @inspection.dup
    end

    private

    def bf_truncate(str, limit = 2048, omission = "... (truncated)")
      return str if str.length <= limit

      str[0, limit - omission.length] + omission
    end

    def bf_json_parse(json)
      return nil unless json.is_a?(String)

      data = ::JSON.parse(json)
      data if data.is_a?(Hash) || data.is_a?(Array)
    rescue ::JSON::ParserError
      nil
    end

    def bf_json_dump(data)
      ::JSON.generate(data, space: " ", object_nl: " ", array_nl: " ")
    end

    def bf_dump(data)
      # 1) String#inspect returns \x{XXXX} for the encoding other than Unicode
      # 2) [1..-2] removes leading and trailing " added by String#inspect
      # 3) gsub(/\\"/, "\"") unescapes "
      data.inspect.gsub(/\\"/, "\"")[1..-2]
    end

    def bf_protect_data(data)
      return data.map { bf_protect_data(_1) } if data.is_a?(Array)
      return data unless data.is_a?(Hash)

      signs = BetterFaraday.sensitive_data_signs

      data.each_with_object({}) do |(key, value), memo|
        normalized_key = key.to_s

        memo[key] = if signs.any? { |r| normalized_key.match?(r) }
          "SECRET"
        else
          bf_protect_data(value)
        end
      end
    end

    def bf_inspect
      request_headers_hash = env.bf_request_headers
      if !request_headers_hash.is_a?(Hash) && request_headers_hash.respond_to?(:to_hash)
        request_headers_hash = request_headers_hash.to_hash
      end
      request_headers_hash = {} if request_headers_hash.nil?

      request_body = env.bf_request_body.then { _1.is_a?(String) ? _1 : _1.to_s }
      request_byte_count = request_body.bytesize

      request_is_json = request_headers_hash.any? do |k, v|
        k.to_s.downcase == "content-type" && v.to_s.match?(%r{\b(?:application|text)/json\b}i)
      end

      request_json = bf_json_parse(request_body)&.then { bf_json_dump(bf_protect_data(_1)) } if request_is_json

      request_byte_label = request_byte_count == 1 ? "byte" : "bytes"

      response_headers_hash = env.response_headers
      if !response_headers_hash.is_a?(Hash) && response_headers_hash.respond_to?(:to_hash)
        response_headers_hash = response_headers_hash.to_hash
      end
      response_headers_hash = {} if response_headers_hash.nil?

      response_body = env.body.then { _1.is_a?(String) ? _1 : _1.to_s }
      response_byte_count = response_body.bytesize

      response_is_json = response_headers_hash.any? do |k, v|
        k.to_s.downcase == "content-type" && v.to_s.match?(%r{\b(?:application|text)/json\b}i)
      end

      response_json = bf_json_parse(response_body)&.then { bf_json_dump(bf_protect_data(_1)) } if response_is_json

      response_byte_label = response_byte_count == 1 ? "byte" : "bytes"

      lines = [
        "-- HTTP #{status} #{reason_phrase} --".gsub(/\s+/, " ").upcase,
        "",
        "-- Request URL --",
        env.url.to_s,
        "",
        "-- Request Method --",
        env.method.to_s.upcase,
        "",
        "-- Request Headers --",
        if !request_headers_hash.nil?
          bf_json_dump(bf_protect_data(request_headers_hash))
        else
          env.bf_request_headers.to_s.inspect.gsub(/\\"/, "\"")[1..-2]
        end.then { bf_truncate(_1) },
        "",

        %[-- Request Body (#{request_byte_count} #{request_byte_label}) --],
        if !request_json.nil?
          request_json
        else
          bf_dump(request_body)
        end.then { bf_truncate(_1) },
        "",

        "-- Request Sent At --",
        env.bf_request_sent_at.nil? ? "N/A" : env.bf_request_sent_at.strftime("%Y-%m-%d %H:%M:%S.%3N UTC"),
        "",

        "-- Response Headers --",
        if !response_headers_hash.nil?
          bf_json_dump(bf_protect_data(response_headers_hash))
        else
          bf_dump(env.response_headers)
        end.then { bf_truncate(_1) },
        "",

        %[-- Response Body (#{response_byte_count} #{response_byte_label}) --],
        if !response_json.nil?
          response_json
        else
          bf_dump(response_body)
        end.then { bf_truncate(_1) },
        ""
      ]

      if env.bf_response_received_at && env.bf_request_sent_at
        lines.concat [
          "-- Response Received At --",
          env.bf_response_received_at.strftime("%Y-%m-%d %H:%M:%S.%3N UTC"),
          "",
          "-- Response Received In --",
          "#{((env.bf_response_received_at.to_f - env.bf_request_sent_at.to_f) * 1000.0).ceil(3)}ms",
          ""
        ]
      end

      lines.join("\n").freeze
    end
  end
end

module BetterFaraday
  class HTTPError < Faraday::Error
    def initialize(response)
      super(response.inspect, response)
    end

    def inspect
      %(#{self.class}\n\n#{response.inspect})
    end
  end

  class HTTP3xx < HTTPError; end

  class HTTP300 < HTTP3xx; end

  class HTTP301 < HTTP3xx; end

  class HTTP302 < HTTP3xx; end

  class HTTP303 < HTTP3xx; end

  class HTTP304 < HTTP3xx; end

  class HTTP307 < HTTP3xx; end

  class HTTP308 < HTTP3xx; end

  class HTTP4xx < HTTPError; end

  class HTTP400 < HTTP4xx; end

  class HTTP401 < HTTP4xx; end

  class HTTP403 < HTTP4xx; end

  class HTTP404 < HTTP4xx; end

  class HTTP408 < HTTP4xx; end

  class HTTP422 < HTTP4xx; end

  class HTTP429 < HTTP4xx; end

  class HTTP5xx < HTTPError; end

  class HTTP500 < HTTP5xx; end

  class HTTP502 < HTTP5xx; end

  class HTTP503 < HTTP5xx; end

  class << self
    attr_accessor :sensitive_data_signs, :logger

    def get_value(object, object_name, field_name, location)
      is_set = object.instance_variable_get("@#{field_name}_set")
      value = object.instance_variable_get("@#{field_name}")

      logger.debug do
        %([#{location}] Getting #{object_name}.#{field_name}: #{value.inspect}#{' (not set)' unless is_set})
      end

      value
    end

    def set_value(object, object_name, field_name, new_value, location)
      is_set = object.instance_variable_get("@#{field_name}_set")

      logger.debug do
        %([#{location}] #{is_set ? 'Overwriting' : 'Setting'} #{object_name}.#{field_name} = #{new_value.inspect})
      end

      object.instance_variable_set("@#{field_name}", new_value)
      object.instance_variable_set("@#{field_name}_set", true)
    end
  end

  # Local variable to DRY up regular expressions for typical key formats
  # (snake_case, kebab-case, spaced, or camelCase with no separator)
  separator = "[_ -]?"

  self.sensitive_data_signs = [
    # Passwords and passphrases
    /pass#{separator}(?:word|phrase)/i,
    # Authorization headers or keys
    /authorization/i,
    # Secrets (client_secret, app_secret, etc.)
    /secret/i,
    # Various tokens (access_token, refresh_token, csrf_token, bearer_token, auth_token, or just token)
    /(?:access|refresh|auth|bearer|csrf|authorization)?#{separator}token/i,
    # API keys (api_key, apikey, x_api_key)
    /api#{separator}key/i,
    # Private keys
    /private#{separator}key/i,
    # Crypto mnemonics
    /mnemonic/i,
    # Session IDs
    /session#{separator}id/i,
    # Credit card CVV/CVC
    /cv[vc]/i,
    # Credit card numbers
    /(?:credit|bank)?#{separator}card#{separator}number/i,
    # Crypto seed phrases
    /seed#{separator}phrase/i,
    # JWT
    /jwt/i
  ].each(&:freeze)

  self.logger = Logger.new(File::NULL, level: Logger::WARN)
end
