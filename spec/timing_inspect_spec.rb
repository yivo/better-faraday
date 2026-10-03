# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe "BetterFaraday Timing Formatting in Inspect" do
  let(:time_sent) { Time.parse("2026-10-03 10:00:00.000 UTC") }
  let(:time_received) { Time.parse("2026-10-03 10:00:00.125 UTC") } # Exactly 125ms later

  let(:env) do
    Faraday::Env.from(
      method: :get,
      url: URI("https://api.example.com/time"),
      status: 200,
      reason_phrase: "OK",
      request_headers: {},
      request_body: "",
      response_headers: {},
      body: ""
    )
  end

  let(:response) { Faraday::Response.new(env) }

  before do
    response.env.instance_variable_set(:@bf_request_sent_at, time_sent)
    response.env.instance_variable_set(:@bf_response_received_at, time_received)
  end

  it "calculates and formats the request duration correctly" do
    inspection = response.inspect

    # Check timestamps formatting
    expect(inspection).to include("-- Request Sent At --\n2026-10-03 10:00:00.000 UTC")
    expect(inspection).to include("-- Response Received At --\n2026-10-03 10:00:00.125 UTC")

    # Check difference calculation in milliseconds
    expect(inspection).to include("-- Response Received In --\n125.0ms")
  end

  it "skips timing block if timestamps are missing" do
    response.env.instance_variable_set(:@bf_request_sent_at, nil)
    response.env.instance_variable_set(:@bf_response_received_at, nil)

    inspection = response.inspect

    expect(inspection).to include("-- Request Sent At --\nN/A")
    expect(inspection).not_to include("-- Response Received At --")
    expect(inspection).not_to include("-- Response Received In --")
  end
end
