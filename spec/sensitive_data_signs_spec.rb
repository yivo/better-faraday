# frozen_string_literal: true

require "spec_helper"

RSpec.describe BetterFaraday do
  describe "Sensitive data masking" do
    let(:request_headers) do
      {
        "Authorization" => "Bearer super-secret-token",
        "X-Api-Key" => "key-12345",
        "Content-Type" => "application/json"
      }
    end

    let(:request_body) do
      {
        user_id: 42,
        password: "my_password123",
        pass_phrase: "open sesame",
        client_secret: "secret_abc",
        mnemonic: "abandon ability able about",
        privateKey: "pk_live_123",
        "api-key" => "dash-key-123",
        seed_phrase: "word word word"
      }.to_json
    end

    let(:response_headers) do
      {
        "Set-Cookie" => "session_id=xyz987; HttpOnly",
        "Content-Type" => "application/json"
      }
    end

    let(:response_body) do
      {
        status: "success",
        data: {
          access_token: "jwt_token_here",
          refresh_token: "refresh_token_here",
          csrfToken: "csrf_123",
          credit_card_number: "4111-1111-1111-1111",
          cvv: "123",
          public_info: "visible_text"
        }
      }.to_json
    end

    let(:env) do
      Faraday::Env.from(
        method: :post,
        url: URI("https://api.example.com/login"),
        status: 200,
        reason_phrase: "OK",
        request_headers: request_headers,
        request_body: request_body,
        response_headers: response_headers,
        body: response_body
      )
    end

    let(:response) { Faraday::Response.new(env) }

    before do
      # Apply variables directly to response.env as Faraday duplicates the Env object
      response.env.instance_variable_set(:@bf_request_sent_at, Time.now.utc)
      response.env.instance_variable_set(:@bf_response_received_at, Time.now.utc)
      response.env.instance_variable_set(:@bf_request_headers, request_headers)
      response.env.instance_variable_set(:@bf_request_body, request_body)
    end

    it "masks sensitive information in request headers" do
      inspection = response.inspect

      expect(inspection).to include('"Authorization": "SECRET"')
      expect(inspection).to include('"X-Api-Key": "SECRET"')
      # Ensure safe headers are not masked
      expect(inspection).to include('"Content-Type": "application/json"')
    end

    it "masks sensitive information in the request JSON body" do
      inspection = response.inspect

      expect(inspection).to include('"password": "SECRET"')
      expect(inspection).to include('"pass_phrase": "SECRET"')
      expect(inspection).to include('"client_secret": "SECRET"')
      expect(inspection).to include('"mnemonic": "SECRET"')
      # Testing camelCase conversion masking
      expect(inspection).to include('"privateKey": "SECRET"')

      # Ensure safe data is not masked
      expect(inspection).to include('"user_id": 42')
    end

    it "masks sensitive information in the response JSON body" do
      inspection = response.inspect

      expect(inspection).to include('"access_token": "SECRET"')
      expect(inspection).to include('"refresh_token": "SECRET"')
      expect(inspection).to include('"csrfToken": "SECRET"')
      expect(inspection).to include('"credit_card_number": "SECRET"')
      expect(inspection).to include('"cvv": "SECRET"')

      # Ensure safe data is not masked
      expect(inspection).to include('"status": "success"')
      expect(inspection).to include('"public_info": "visible_text"')
    end
  end
end
