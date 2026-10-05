# frozen_string_literal: true

require "spec_helper"

RSpec.describe "BetterFaraday with Faraday JSON Middlewares" do
  let(:conn) do
    Faraday.new(url: "https://api.example.com") do |f|
      f.request :json
      f.response :json

      f.adapter :test do |stub|
        stub.post("/process") do |env|
          [
            200,
            { "Content-Type" => "application/json" },
            '{"status": "success", "access_token": "secret_token_123", "user_id": 42}'
          ]
        end
      end
    end
  end

  it "safely inspects and masks data when bodies are transformed by JSON middlewares" do
    request_payload = {
      action: "login",
      password: "my_super_secret_password"
    }

    response = conn.post("/process", request_payload)

    expect(response.body).to be_a(Hash)
    expect(response.body["status"]).to eq("success")

    inspection = response.inspect

    expect(inspection).to include('"password": "SECRET"')
    expect(inspection).not_to include("my_super_secret_password")
    expect(inspection).to include('"action": "login"')

    expect(inspection).to include('"access_token": "SECRET"')
    expect(inspection).not_to include("secret_token_123")
    expect(inspection).to include('"user_id": 42')

    expect(inspection).not_to include("=>")
  end
end
