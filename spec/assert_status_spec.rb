# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BetterFaraday Response Assertions" do
  let(:conn) { Faraday.new(url: "https://api.example.com") }

  before do
    stub_request(:get, "https://api.example.com/200").to_return(status: 200, body: "OK")
    stub_request(:get, "https://api.example.com/204").to_return(status: 204, body: "")
    stub_request(:get, "https://api.example.com/302").to_return(status: 302, body: "Found")
    stub_request(:get, "https://api.example.com/404").to_return(status: 404, body: "Not Found")
    stub_request(:get, "https://api.example.com/422").to_return(status: 422, body: "Unprocessable")
    stub_request(:get, "https://api.example.com/500").to_return(status: 500, body: "Server Error")
    stub_request(:get, "https://api.example.com/599").to_return(status: 599, body: "Unknown Error")
  end

  describe "#assert_200!" do
    it "returns the response if status is 200" do
      response = conn.get("/200")
      expect(response.assert_200!).to eq(response)
    end

    it "raises HTTPError if status is not 200" do
      response = conn.get("/204")
      expect { response.assert_200! }.to raise_error(BetterFaraday::HTTPError)
    end
  end

  describe "#assert_2xx!" do
    it "returns the response if status is within 200..299" do
      expect(conn.get("/200").assert_2xx!).to be_a(Faraday::Response)
      expect(conn.get("/204").assert_2xx!).to be_a(Faraday::Response)
    end

    it "raises HTTP302 for 302 status" do
      response = conn.get("/302")
      expect { response.assert_2xx! }.to raise_error(BetterFaraday::HTTP302)
    end
  end

  describe "#assert_status!" do
    it "accepts a range of statuses" do
      response = conn.get("/404")
      expect(response.assert_status!(400..499)).to eq(response)
    end

    it "accepts a single integer status" do
      response = conn.get("/422")
      expect(response.assert_status!(422)).to eq(response)
    end

    it "raises the exact mapped HTTP4xx error" do
      response = conn.get("/404")
      expect { response.assert_status!(200) }.to raise_error(BetterFaraday::HTTP404)

      response_422 = conn.get("/422")
      expect { response_422.assert_status!(200) }.to raise_error(BetterFaraday::HTTP422)
    end

    it "raises the exact mapped HTTP500 error" do
      response = conn.get("/500")
      expect { response.assert_status!(200) }.to raise_error(BetterFaraday::HTTP500)
    end

    it "falls back to the generic HTTP5xx error for unknown 5xx statuses" do
      response = conn.get("/599")
      expect { response.assert_status!(200) }.to raise_error(BetterFaraday::HTTP5xx)
    end
  end
end
