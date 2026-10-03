# better-faraday

A lightweight gem extending Faraday (the popular Ruby HTTP client) with useful features, extensive logging, and smart HTTP exceptions—without breaking the standard API.

## Requirements

* Ruby >= 2.7.0, < 5.0 (Fully compatible with Ruby 3.x and 4.x)
* Faraday >= 1.0, < 3.0

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'better-faraday'
```

## Usage & Features

### 1. Advanced Exception Handling

Better Faraday automatically defines semantic HTTP exceptions and allows you to enforce strict status checks directly on the response object:

```ruby
response = Faraday.get('https://api.example.com/data')

# Raises BetterFaraday::HTTP404 if the status is 404
# Raises BetterFaraday::HTTP5xx if the status is 500-599
response.assert_2xx! 

# Or check specific ranges/codes:
response.assert_status!(200)
response.assert_status!(200..204)
```

### 2. Comprehensive Response Inspection

Better Faraday enriches `response.inspect` to output detailed, formatted information about the entire lifecycle of the request, including headers, parsed JSON payloads, execution time, and masked sensitive data.

```ruby
begin
  response.assert_2xx!
rescue BetterFaraday::HTTPError => e
  # Will print a beautifully formatted payload showing what went wrong,
  # while masking passwords and tokens with "SECRET".
  puts e.inspect 
end
```
