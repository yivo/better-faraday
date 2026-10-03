# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BetterFaraday Response Inspection Truncation" do
  let(:long_string) { "A" * 3000 }
  let(:limit) { 2048 }
  let(:expected_omission) { "... (truncated)" }

  let(:env) do
    Faraday::Env.from(
      method: :get,
      url: URI("https://api.example.com/large_payload"),
      status: 200,
      reason_phrase: "OK",
      request_headers: { "Content-Type" => "text/plain" },
      request_body: "small_request",
      response_headers: { "Content-Type" => "text/plain" },
      body: long_string
    )
  end

  let(:response) { Faraday::Response.new(env) }

  before do
    response.env.instance_variable_set(:@bf_request_headers, { "Content-Type" => "text/plain" })
    response.env.instance_variable_set(:@bf_request_body, "small_request")
  end

  it "truncates request and response bodies exceeding 2048 characters" do
    inspection = response.inspect

    expect(inspection).to include(expected_omission)
    expect(inspection).not_to include(long_string)

    # Verify that the truncation mark is located in the answer section.
    body_section = inspection.split("-- Response Body (3000 bytes) --").last
    expect(body_section).to include(expected_omission)
  end
end
