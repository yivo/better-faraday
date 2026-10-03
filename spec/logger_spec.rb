# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "logger"

RSpec.describe "BetterFaraday Debug Logger" do
  let(:log_io) { StringIO.new }
  let(:custom_logger) { Logger.new(log_io, level: Logger::DEBUG) }

  before do
    @original_logger = BetterFaraday.logger
    BetterFaraday.logger = custom_logger
  end

  after do
    BetterFaraday.logger = @original_logger
  end

  it "logs get_value and set_value actions when level is DEBUG" do
    dummy_object = Object.new

    # Trigger a set_value event
    BetterFaraday.set_value(dummy_object, "test_obj", "bf_test_field", "my_value", "TestContext")

    # Trigger an overwrite event
    BetterFaraday.set_value(dummy_object, "test_obj", "bf_test_field", "new_value", "TestContext")

    # Trigger a get_value event
    BetterFaraday.get_value(dummy_object, "test_obj", "bf_test_field", "TestContextGet")

    logs = log_io.string

    # Verify the initial setting log
    expect(logs).to include('[TestContext] Setting test_obj.bf_test_field = "my_value"')

    # Verify the overwriting log
    expect(logs).to include('[TestContext] Overwriting test_obj.bf_test_field = "new_value"')

    # Verify the getting log
    expect(logs).to include('[TestContextGet] Getting test_obj.bf_test_field: "new_value"')
  end

  it "silences output when log level is WARN" do
    BetterFaraday.logger.level = Logger::WARN
    dummy_object = Object.new

    BetterFaraday.set_value(dummy_object, "test_obj", "bf_test_field", "silent_value", "TestContext")

    expect(log_io.string).to be_empty
  end
end
