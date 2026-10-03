# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BetterFaraday Array Masking" do
  let(:array_body) do
    [
      { user_id: 1, password: "secret_password_1", public_info: "user_a" },
      { user_id: 2, password: "secret_password_2", public_info: "user_b" }
    ].to_json
  end

  let(:env) do
    Faraday::Env.from(
      method: :post,
      url: URI("https://api.example.com/batch"),
      status: 200,
      request_headers: { "Content-Type" => "application/json" },
      request_body: array_body,
      response_headers: { "Content-Type" => "application/json" },
      body: array_body
    )
  end

  let(:response) { Faraday::Response.new(env) }

  before do
    response.env.instance_variable_set(:@bf_request_headers, { "Content-Type" => "application/json" })
    response.env.instance_variable_set(:@bf_request_body, array_body)
  end

  it "masks sensitive keys inside arrays of hashes" do
    inspection = response.inspect

    # Sensitive data is masked in all array elements
    expect(inspection).to include('"password": "SECRET"')

    # Original sensitive strings should not leak
    expect(inspection).not_to include("secret_password_1")
    expect(inspection).not_to include("secret_password_2")

    # Safe data remains untouched
    expect(inspection).to include('"user_id": 1')
    expect(inspection).to include('"user_id": 2')
    expect(inspection).to include('"public_info": "user_a"')
  end
end
