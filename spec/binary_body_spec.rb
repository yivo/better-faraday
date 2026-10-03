# frozen_string_literal: true

require "spec_helper"
require "securerandom"

RSpec.describe "BetterFaraday Binary Data Handling" do
  # Generate 3000 bytes of random binary data (invalid UTF-8)
  let(:binary_payload) { SecureRandom.random_bytes(3000) }
  let(:expected_omission) { "... (truncated)" }

  let(:env) do
    Faraday::Env.from(
      method: :post,
      url: URI("https://api.example.com/upload"),
      status: 200,
      reason_phrase: "OK",
      request_headers: { "Content-Type" => "application/octet-stream" },
      request_body: binary_payload,
      response_headers: { "Content-Type" => "image/png" },
      body: binary_payload
    )
  end

  let(:response) { Faraday::Response.new(env) }

  before do
    response.env.instance_variable_set(:@bf_request_headers, { "Content-Type" => "application/octet-stream" })
    response.env.instance_variable_set(:@bf_request_body, binary_payload)
  end

  it "safely inspects binary data without encoding crashes and truncates it" do
    inspection = nil

    # Ensure no Encoding::UndefinedConversionError or similar exceptions are raised
    expect { inspection = response.inspect }.not_to raise_error

    # Verify that the byte count accurately reflects the binary size
    expect(inspection).to include("-- Request Body (3000 bytes) --")
    expect(inspection).to include("-- Response Body (3000 bytes) --")

    # Verify that the output is safely truncated to avoid console memory bloat
    expect(inspection).to include(expected_omission)

    # The raw binary string should not be fully present in the output
    expect(inspection).not_to include(binary_payload)
  end
end
