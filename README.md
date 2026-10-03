# better-faraday

A lightweight gem extending Faraday (the popular Ruby HTTP client) with useful features, extensive logging, and smart HTTP exceptions—without breaking the standard API.

## Requirements

* **Ruby** >= 2.7.0, < 5.0 (Fully compatible with Ruby 3.x and 4.x)
* **Faraday** >= 1.0, < 3.0
* **Zero dependencies**

## Installation

Add this line to your application's Gemfile:

```ruby
gem "better-faraday", "~> 3.1"
```

## Usage & Features

### 1. Advanced Exception Handling

Better Faraday automatically defines semantic HTTP exceptions and allows you to enforce strict status checks directly on the response object.

```ruby
response = Faraday.get("https://api.example.com/data")

# Raises BetterFaraday::HTTP404 if the status is 404
# Raises BetterFaraday::HTTP5xx if the status is 500-599
response.assert_2xx! 

# Or check specific ranges/codes:
response.assert_status!(200)
response.assert_status!(200..204)
```

If an exception is raised, its `.message` and `.inspect` will contain a beautifully formatted payload showing exactly what went wrong.

### 2. Comprehensive Response Inspection

Better Faraday enriches `response.inspect` to output detailed, formatted information about the entire lifecycle of the request. It automatically parses JSON bodies for readability, calculates request duration, and safely truncates huge payloads (over 2048 bytes) to prevent memory bloating in your logs.

```ruby
begin
  response.assert_2xx!
rescue BetterFaraday::HTTPError => e
  puts e.inspect 
end
```

**Output example:**
```text
BetterFaraday::HTTP422

-- HTTP 422 UNPROCESSABLE ENTITY --

-- Request URL --
https://api.example.com/users

-- Request Method --
POST

-- Request Headers --
{ "Content-Type": "application/json", "Authorization": "SECRET" }

-- Request Body (48 bytes) --
{ "email": "user@test.com", "password": "SECRET" }

-- Request Sent At --
2026-10-03 10:00:00.000 UTC

-- Response Headers --
{ "Content-Type": "application/json" }

-- Response Body (35 bytes) --
{ "error": "Email already exists" }

-- Response Received At --
2026-10-03 10:00:00.125 UTC

-- Response Received In --
125.0ms
```

### 3. Smart Sensitive Data Masking

Better Faraday protects your logs by aggressively masking sensitive information in both headers and JSON bodies. Out of the box, it safely masks:
* 
* Passwords and passphrases
* API keys and secrets
* Tokens (Access, Refresh, Bearer, CSRF, JWT)
* Authorization headers
* Credit Card numbers and CVV/CVC codes
* Crypto mnemonics and seed phrases

The masking algorithm is highly performant and seamlessly handles `snake_case`, `camelCase`, `kebab-case`, and spaced keys.

**Adding Custom Masking Rules:**
You can easily add your own regex patterns to the masking engine:

```ruby
BetterFaraday.sensitive_data_signs << /my_custom_secret_key/i.freeze
```

### 4. Bulletproof Middleware & Adapter Compatibility

Better Faraday securely captures request data regardless of the adapter you use:
* **Standard Adapters:** Fully supports `Net::HTTP` and `Net::HTTP::Persistent`, capturing the exact wire headers mutated during transport.
* **Test Adapters:** Perfectly compatible with `Faraday::Adapter::Test` and `WebMock` using an eager-fallback mechanism.
* **Multipart & IO Streams:** Safely reads and logs `File` or `StringIO` upload payloads, ensuring the stream is automatically rewound back to position `0` so the HTTP adapter doesn't send an empty request.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
