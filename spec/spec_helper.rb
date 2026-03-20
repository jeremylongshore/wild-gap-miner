# frozen_string_literal: true

require 'wild_gap_miner'

Dir[File.join(File.dirname(__FILE__), 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.include TelemetryFixtures

  config.before do
    WildGapMiner.reset_configuration!
  end

  config.order = :random
  config.color = true
end
