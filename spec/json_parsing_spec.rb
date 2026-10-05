# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BetterFaraday Pre-parsed Bodies & Status Formatting" do
  let(:env) do
    Faraday::Env.from(
      method: :post,
      url: URI("https://api.example.com/json"),
      status: 422,
      reason_phrase: "UNKNOWN", # Faraday sometimes defaults to UNKNOWN
      request_headers: { "Content-Type" => "application/json" },
      # Simulate body already parsed by Faraday JSON request middleware
      request_body: { "account_type" => "trading", "password" => "secret_123" },
      response_headers: { "Content-Type" => "application/json; charset=UTF-8" },
      # Simulate body already parsed by Faraday JSON response middleware
      body: { "code" => 40010001, "message" => "Invalid currency" }
    )
  end

  let(:response) { Faraday::Response.new(env) }

  before do
    response.env.instance_variable_set(:@bf_request_headers, { "Content-Type" => "application/json" })
    # This is what gets captured by the middleware
    response.env.instance_variable_set(:@bf_request_body, { "account_type" => "trading", "password" => "secret_123" })
  end

  it "formats 'UNKNOWN' reason phrase correctly to UNPROCESSABLE ENTITY" do
    inspection = response.inspect
    expect(inspection).to include("-- HTTP 422 UNPROCESSABLE ENTITY --")
  end

  it "formats pre-parsed Hash response bodies to JSON strings and masks data" do
    inspection = response.inspect

    # Request Hash
    expect(inspection).to include('"password": "SECRET"')
    expect(inspection).to include('"account_type": "trading"')

    # Response Hash
    expect(inspection).to include('"code": 40010001')
    expect(inspection).to include('"message": "Invalid currency"')

    # Ensure Ruby hash notation is absolutely gone
    expect(inspection).not_to include("=>")
  end

  it "resolves empty reason phrases to their Net::HTTP default strings" do
    response.env.status = 201
    response.env.reason_phrase = ""

    expect(response.inspect).to include("-- HTTP 201 CREATED --")
  end
end
