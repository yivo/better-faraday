# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BetterFaraday Reason Phrase Formatting" do
  let(:env) do
    Faraday::Env.from(
      method: :get,
      url: URI("https://api.example.com/status"),
      status: status,
      reason_phrase: reason_phrase,
      request_headers: {},
      request_body: "",
      response_headers: {},
      body: ""
    )
  end

  let(:response) { Faraday::Response.new(env) }

  context "when reason_phrase is UNKNOWN" do
    let(:status) { 422 }
    let(:reason_phrase) { "UNKNOWN" }

    it "resolves to UNPROCESSABLE ENTITY using Net::HTTP mapping" do
      expect(response.inspect).to include("-- HTTP 422 UNPROCESSABLE ENTITY --")
    end
  end

  context "when reason_phrase is empty" do
    let(:status) { 201 }
    let(:reason_phrase) { "   " }

    it "resolves to CREATED using Net::HTTP mapping" do
      expect(response.inspect).to include("-- HTTP 201 CREATED --")
    end
  end

  context "when reason_phrase is valid" do
    let(:status) { 418 }
    let(:reason_phrase) { "I Am A Teapot" }

    it "uses the provided reason phrase" do
      expect(response.inspect).to include("-- HTTP 418 I AM A TEAPOT --")
    end
  end

  context "when status code is completely unknown" do
    let(:status) { 999 }
    let(:reason_phrase) { "UNKNOWN" }

    it "safely falls back to UNKNOWN if no Net::HTTP mapping exists" do
      expect(response.inspect).to include("-- HTTP 999 UNKNOWN --")
    end
  end
end
