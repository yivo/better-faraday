# frozen_string_literal: true

require "spec_helper"
require "tempfile"

require "faraday/multipart"

RSpec.describe "BetterFaraday Multipart Requests" do
  let(:conn) do
    Faraday.new("https://api.example.com") do |f|
      f.request :multipart
      f.adapter :test do |stub|
        stub.post("/upload") { [200, { "Content-Type" => "application/json" }, '{"status":"ok"}'] }
      end
    end
  end

  it "safely processes File objects in multipart requests without consuming the stream" do
    Tempfile.create("test_upload") do |file|
      file.write("file content data")
      file.rewind

      payload = {
        file: Faraday::Multipart::FilePart.new(file, "text/plain")
      }

      response = conn.post("/upload", payload)
      env = response.env

      # Verify the body was cached as a String representation
      expect(env.bf_request_body).to be_a(String)
      expect(env.bf_request_body).to include("file content data")

      # Verify the file stream was properly rewound
      expect(file.pos).to eq(0)
      expect(file.read).to eq("file content data")
    end
  end
end
