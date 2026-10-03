# frozen_string_literal: true

require "spec_helper"
require "socket"

begin
  require "faraday/net_http_persistent"
rescue LoadError
  # Ignore if not available in this Faraday version
end

RSpec.describe "Faraday Adapters Integration" do
  before(:all) do
    # Spinning up a real local server on a random port for Net::HTTP tests
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]

    @server_thread = Thread.new do
      loop do
        client = @server.accept
        # Read the request up to the empty line (the end of the HTTP headers)
        while (line = client.gets)
          break if line == "\r\n"
        end
        # We respond with a success status
        client.print "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nOK"
        client.close
      end
    end
  end

  after(:all) do
    @server_thread.kill
    @server.close
  end

  let(:url) { "http://127.0.0.1:#{@port}/test" }

  shared_examples "an adapter capturing headers" do |adapter_name|
    it "captures request headers and execution times" do
      # Allowing real local requests for WebMock
      WebMock.allow_net_connect!

      connection = Faraday.new(url: url) do |builder|
        builder.adapter adapter_name
      end

      response = connection.get do |req|
        req.headers["X-Custom-Test"] = "Hello"
      end

      env = response.env

      expect(env.bf_request_sent_at).to be_a(Time)
      expect(env.bf_response_received_at).to be_a(Time)

      # Headers must be a hash
      expect(env.bf_request_headers).to be_a(Hash)

      # We verify that our custom header has been received
      # We use `.match?` or `downcase`, since `Net::HTTP` might change the case
      header_keys = env.bf_request_headers.keys.map(&:downcase)
      expect(header_keys).to include("x-custom-test")

      WebMock.disable_net_connect!(allow_localhost: true)
    end
  end

  describe "Net::HTTP Adapter" do
    it_behaves_like "an adapter capturing headers", :net_http
  end

  describe "Net::HTTP::Persistent Adapter" do
    before do
      skip "Adapter not available" unless Faraday::Adapter.const_defined?(:NetHttpPersistent)
    end

    it_behaves_like "an adapter capturing headers", :net_http_persistent
  end

  describe "Test Adapter (No Net::HTTP)" do
    it "relies on the fallback mechanism from Adapter#call" do
      stubs = Faraday::Adapter::Test::Stubs.new do |stub|
        stub.get("/test") { [200, { "Content-Type" => "text/plain" }, "OK"] }
      end

      connection = Faraday.new do |builder|
        builder.adapter :test, stubs
      end

      response = connection.get("/test") do |req|
        req.headers["X-Test-Adapter-Header"] = "Mocked"
      end

      env = response.env

      expect(env.bf_request_sent_at).to be_a(Time)
      expect(env.bf_response_received_at).to be_a(Time)

      expect(env.bf_request_headers).to be_a(Hash)
      expect(env.bf_request_headers["X-Test-Adapter-Header"]).to eq("Mocked")
    end
  end
end
