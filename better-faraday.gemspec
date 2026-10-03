# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name                  = "better-faraday"
  s.version               = "3.1.1"
  s.author                = "Yaroslav Konoplov"
  s.email                 = "eahome00@gmail.com"
  s.summary               = "Extends Faraday with useful features"
  s.description           = "A gem extending Faraday HTTP client with useful features"
  s.homepage              = "https://github.com/yivo/better-faraday"
  s.license               = "MIT"

  # Ruby requirements
  s.required_ruby_version = [">= 2.7.0", "< 5.0"]

  s.files                 = `git ls-files -z`.split("\x0")
  s.test_files            = `git ls-files -z -- {test,spec,features}/*`.split("\x0")
  s.require_paths         = ["lib"]

  # Runtime dependencies
  s.add_dependency "faraday", ">= 1.0", "< 3.0"

  # Development and test dependencies
  s.add_development_dependency "bundler", "~> 4.0"
  s.add_development_dependency "faraday-multipart", "~> 1.2"
  s.add_development_dependency "faraday-net_http_persistent", "~> 2.3"
  s.add_development_dependency "pry-byebug", "~> 3.12"
  s.add_development_dependency "rake", "~> 13.4"
  s.add_development_dependency "rspec", "~> 3.13"
  s.add_development_dependency "webmock", "~> 3.26"
end
