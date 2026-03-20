# frozen_string_literal: true

require 'json'
require 'time'
require 'tmpdir'

require_relative 'wild_gap_miner/version'
require_relative 'wild_gap_miner/errors'
require_relative 'wild_gap_miner/configuration'

require_relative 'wild_gap_miner/models/telemetry_record'
require_relative 'wild_gap_miner/models/export_header'
require_relative 'wild_gap_miner/models/event_record'
require_relative 'wild_gap_miner/models/session_summary'
require_relative 'wild_gap_miner/models/tool_utilization'
require_relative 'wild_gap_miner/models/outcome_distribution'
require_relative 'wild_gap_miner/models/latency_stats'
require_relative 'wild_gap_miner/models/pattern_record'
require_relative 'wild_gap_miner/models/gap'
require_relative 'wild_gap_miner/models/gap_report'

require_relative 'wild_gap_miner/ingestion/record_factory'
require_relative 'wild_gap_miner/ingestion/export_parser'

require_relative 'wild_gap_miner/analyzers/base'
require_relative 'wild_gap_miner/analyzers/denial_analyzer'
require_relative 'wild_gap_miner/analyzers/failure_analyzer'
require_relative 'wild_gap_miner/analyzers/latency_analyzer'
require_relative 'wild_gap_miner/analyzers/utilization_analyzer'
require_relative 'wild_gap_miner/analyzers/coverage_analyzer'
require_relative 'wild_gap_miner/analyzers/pattern_analyzer'

require_relative 'wild_gap_miner/scoring/severity_scorer'
require_relative 'wild_gap_miner/scoring/priority_ranker'

require_relative 'wild_gap_miner/recommendations/engine'

require_relative 'wild_gap_miner/report/builder'

require_relative 'wild_gap_miner/export/json_exporter'
require_relative 'wild_gap_miner/export/markdown_exporter'

module WildGapMiner
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    # Convenience entry point: parse a JSONL file and return a GapReport.
    def analyze(path, config: configuration)
      parser = Ingestion::ExportParser.new(config: config)
      parsed = parser.parse_file(path)
      builder_records = parsed[:records].merge(header: parsed[:header])
      Report::Builder.new(records: builder_records, config: config).build
    end
  end
end
