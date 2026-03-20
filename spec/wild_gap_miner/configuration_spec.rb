# frozen_string_literal: true

RSpec.describe WildGapMiner::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'sets denial_threshold to 0.2' do
      expect(config.denial_threshold).to eq(0.2)
    end

    it 'sets failure_threshold to 0.15' do
      expect(config.failure_threshold).to eq(0.15)
    end

    it 'sets latency_p95_threshold_ms to 500.0' do
      expect(config.latency_p95_threshold_ms).to eq(500.0)
    end

    it 'sets utilization_min_count to 5' do
      expect(config.utilization_min_count).to eq(5)
    end

    it 'sets coverage_min_fraction to 0.3' do
      expect(config.coverage_min_fraction).to eq(0.3)
    end

    it 'sets pattern_min_occurrences to 3' do
      expect(config.pattern_min_occurrences).to eq(3)
    end

    it 'sets max_gaps_per_type to 50' do
      expect(config.max_gaps_per_type).to eq(50)
    end

    it 'sets all severity_weights to 1.0' do
      expect(config.severity_weights.values).to all(eq(1.0))
    end
  end

  describe 'setters' do
    it 'allows setting denial_threshold' do
      config.denial_threshold = 0.4
      expect(config.denial_threshold).to eq(0.4)
    end

    it 'raises ConfigurationError for non-numeric denial_threshold' do
      expect { config.denial_threshold = 'bad' }.to raise_error(WildGapMiner::ConfigurationError)
    end

    it 'raises ConfigurationError when denial_threshold > 1.0' do
      expect { config.denial_threshold = 1.5 }.to raise_error(WildGapMiner::ConfigurationError)
    end

    it 'allows setting failure_threshold' do
      config.failure_threshold = 0.3
      expect(config.failure_threshold).to eq(0.3)
    end

    it 'allows setting latency_p95_threshold_ms' do
      config.latency_p95_threshold_ms = 1000.0
      expect(config.latency_p95_threshold_ms).to eq(1000.0)
    end

    it 'raises ConfigurationError for negative latency threshold' do
      expect { config.latency_p95_threshold_ms = -1.0 }.to raise_error(WildGapMiner::ConfigurationError)
    end

    it 'allows setting utilization_min_count' do
      config.utilization_min_count = 10
      expect(config.utilization_min_count).to eq(10)
    end

    it 'raises ConfigurationError for non-integer utilization_min_count' do
      expect { config.utilization_min_count = 1.5 }.to raise_error(WildGapMiner::ConfigurationError)
    end

    it 'allows setting coverage_min_fraction' do
      config.coverage_min_fraction = 0.5
      expect(config.coverage_min_fraction).to eq(0.5)
    end

    it 'allows setting pattern_min_occurrences' do
      config.pattern_min_occurrences = 5
      expect(config.pattern_min_occurrences).to eq(5)
    end

    it 'raises ConfigurationError for pattern_min_occurrences < 1' do
      expect { config.pattern_min_occurrences = 0 }.to raise_error(WildGapMiner::ConfigurationError)
    end

    it 'allows setting max_gaps_per_type' do
      config.max_gaps_per_type = 100
      expect(config.max_gaps_per_type).to eq(100)
    end

    it 'allows setting severity_weights' do
      config.severity_weights = { denial: 2.0 }
      expect(config.severity_weights[:denial]).to eq(2.0)
    end

    it 'merges severity_weights with defaults' do
      config.severity_weights = { denial: 2.0 }
      expect(config.severity_weights[:failure]).to eq(1.0)
    end

    it 'raises ConfigurationError for non-hash severity_weights' do
      expect { config.severity_weights = 'bad' }.to raise_error(WildGapMiner::ConfigurationError)
    end
  end

  describe '#freeze!' do
    before { config.freeze! }

    it 'prevents further modifications' do
      expect { config.denial_threshold = 0.9 }.to raise_error(FrozenError)
    end

    it 'freezes severity_weights' do
      expect(config.severity_weights).to be_frozen
    end
  end
end
