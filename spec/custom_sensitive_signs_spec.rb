# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BetterFaraday Custom Sensitive Data Signs" do
  let(:custom_regex) { /super_secret_custom_key/i }

  before do
    @original_signs = BetterFaraday.sensitive_data_signs

    BetterFaraday.sensitive_data_signs = (@original_signs + [custom_regex]).freeze
  end

  after do
    BetterFaraday.sensitive_data_signs = @original_signs
  end

  it "masks custom keys defined by the user" do
    headers = {
      "Super-Secret-Custom-Key" => "hidden_header_value",
      "Content-Type" => "application/json"
    }

    env = Faraday::Env.from(
      method: :post,
      url: URI("https://api.example.com/custom"),
      status: 200,
      request_headers: headers,
      request_body: { super_secret_custom_key: "hidden_body_value", safe_key: "visible" }.to_json
    )

    response = Faraday::Response.new(env)
    response.env.instance_variable_set(:@bf_request_headers, headers)
    response.env.instance_variable_set(:@bf_request_body, { super_secret_custom_key: "hidden_body_value", safe_key: "visible" }.to_json)

    inspection = response.inspect

    expect(inspection).to include('"Super-Secret-Custom-Key": "SECRET"')
    expect(inspection).to include('"super_secret_custom_key": "SECRET"')

    expect(inspection).not_to include("hidden_header_value")
    expect(inspection).not_to include("hidden_body_value")

    expect(inspection).to include('"safe_key": "visible"')
  end
end
