# frozen_string_literal: true

RSpec.describe WildGapMiner do
  describe '.configuration' do
    it 'returns a Configuration instance' do
      expect(described_class.configuration).to be_a(WildGapMiner::Configuration)
    end

    it 'returns the same instance on repeated calls' do
      config = described_class.configuration
      expect(described_class.configuration).to be(config)
    end
  end

  describe '.configure' do
    it 'yields the configuration object' do
      expect { |b| described_class.configure(&b) }.to yield_with_args(WildGapMiner::Configuration)
    end

    it 'allows setting configuration values' do
      described_class.configure do |c|
        c.denial_threshold = 0.5
      end
      expect(described_class.configuration.denial_threshold).to eq(0.5)
    end
  end

  describe '.reset_configuration!' do
    it 'creates a fresh Configuration instance' do
      described_class.configure { |c| c.denial_threshold = 0.9 }
      described_class.reset_configuration!
      expect(described_class.configuration.denial_threshold).to eq(0.2)
    end
  end

  describe '.analyze' do
    it 'parses a JSONL file and returns a GapReport' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'test.jsonl')
        File.write(path, valid_jsonl)
        report = described_class.analyze(path)
        expect(report).to be_a(WildGapMiner::Models::GapReport)
      end
    end
  end
end
