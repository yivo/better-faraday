# frozen_string_literal: true

require "spec_helper"

RSpec.describe BetterFaraday::HTTPError do
  let(:env) do
    Faraday::Env.from(
      method: :post,
      url: URI("https://api.example.com/crash"),
      status: 500,
      reason_phrase: "Internal Server Error",
      request_headers: { "Content-Type" => "application/json" },
      request_body: '{"action":"test"}',
      response_headers: { "Content-Type" => "text/plain" },
      body: "Fatal crash on line 42"
    )
  end

  let(:response) { Faraday::Response.new(env) }

  before do
    response.env.instance_variable_set(:@bf_request_sent_at, Time.now.utc)
    response.env.instance_variable_set(:@bf_response_received_at, Time.now.utc)
    response.env.instance_variable_set(:@bf_request_headers, { "Content-Type" => "application/json" })
    response.env.instance_variable_set(:@bf_request_body, '{"action":"test"}')
  end

  describe "#inspect" do
    it "prepends the class name to the detailed response inspection" do
      error = described_class.new(response)
      inspection = error.inspect

      expect(inspection).to start_with("BetterFaraday::HTTPError\n\n")

      expect(inspection).to include("-- HTTP 500 INTERNAL SERVER ERROR --")
      expect(inspection).to include("-- Request URL --\nhttps://api.example.com/crash")
      expect(inspection).to include("Fatal crash on line 42")
    end

    it "dynamically uses the correct subclass name" do
      error_404 = BetterFaraday::HTTP404.new(response)
      error_502 = BetterFaraday::HTTP502.new(response)

      expect(error_404.inspect).to start_with("BetterFaraday::HTTP404\n\n")
      expect(error_502.inspect).to start_with("BetterFaraday::HTTP502\n\n")
    end
  end

  describe "#message" do
    it "uses the full inspection text as the exception message" do
      error = described_class.new(response)

      expect(error.message).to eq(response.inspect)
    end
  end
end
