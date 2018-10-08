# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "faraday"
require "faraday/error"
require "faraday/options"
require "faraday/response"

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
  end

  class Response
    def assert_2xx!
      return self if status >= 200 && status <= 299
      klass = if status == 422
        Faraday::HTTP422
      elsif status >= 400 && status <= 499
        Faraday::HTTP4xx
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
        ::JSON.generate(env.request_headers.tap { |x| x["Authorization"] = "SECRET" if x.key?("Authorization") }),
        "",
        "-- Request body --",
        env.request_body.to_s,
        "",
        "-- Response headers --",
        ::Hash === env.response_headers ? ::JSON.generate(env.response_headers) : "",
        "",
        "-- Response body --",
        env.body.to_s,
        ""
      ].join("\n")
    end
  end

  class HTTP4xx < Error

  end

  class HTTP422 < HTTP4xx

  end
end
