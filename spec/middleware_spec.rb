# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe "BetterFaraday Middleware and Environment" do
  let(:conn) { Faraday.new(url: "https://api.example.com") }

  before do
    stub_request(:post, "https://api.example.com/data")
      .to_return(status: 201, headers: { "Content-Type" => "application/json" }, body: '{"ok":true}')
  end

  describe "Timing and Headers tracking" do
    it "injects timestamps and headers into the Faraday::Env" do
      response = conn.post("/data") do |req|
        req.headers["X-Custom-Header"] = "TestValue"
        req.body = "raw string body"
      end

      env = response.env

      # Verify timestamps are captured
      expect(env.bf_request_sent_at).to be_a(Time)
      expect(env.bf_response_received_at).to be_a(Time)
      expect(env.bf_response_received_at).to be >= env.bf_request_sent_at

      # Verify request payload is cached
      expect(env.bf_request_body).to eq("raw string body")

      # require "pry-byebug" rescue LoadError
      # binding.respond_to?(:pry) ? binding.pry : Kernel.puts("Unable to start REPL")

      # Verify request headers are captured through the Net::HTTP patch
      expect(env.bf_request_headers).to be_a(Hash)
      # Net::HTTP lowercases headers during transport
      expect(env.bf_request_headers["X-Custom-Header"]).to eq("TestValue")
    end
  end

  describe "IO body rewinding" do
    it "safely reads IO objects and rewinds them to prevent empty bodies" do
      io_body = StringIO.new("streamed io content")

      response = conn.post("/data") do |req|
        req.body = io_body
      end

      env = response.env

      # The middleware should have read the IO object into a string for logging
      expect(env.bf_request_body).to eq("streamed io content")

      # The IO object should have been rewound, meaning its pointer is back at 0
      expect(io_body.pos).to eq(0)

      # It should still be readable by the actual HTTP client
      expect(io_body.read).to eq("streamed io content")
    end
  end
end
