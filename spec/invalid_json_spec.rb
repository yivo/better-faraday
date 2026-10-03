# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BetterFaraday Invalid JSON Handling" do
  let(:broken_json) { "{ broken: json, 'missing_quotes': true }" }
  let(:html_error) { "<html><body>502 Bad Gateway</body></html>" }

  let(:env) do
    Faraday::Env.from(
      method: :post,
      url: URI("https://api.example.com/data"),
      status: 502,
      reason_phrase: "Bad Gateway",
      request_headers: { "Content-Type" => "application/json" },
      request_body: broken_json,
      response_headers: { "Content-Type" => "application/json" },
      body: html_error
    )
  end

  let(:response) { Faraday::Response.new(env) }

  before do
    response.env.instance_variable_set(:@bf_request_headers, { "Content-Type" => "application/json" })
    response.env.instance_variable_set(:@bf_request_body, broken_json)
  end

  it "falls back to raw string output without raising JSON::ParserError" do
    inspection = nil

    expect { inspection = response.inspect }.not_to raise_error

    expect(inspection).to include(broken_json)
    expect(inspection).to include(html_error)
  end
end
