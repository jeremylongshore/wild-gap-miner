# frozen_string_literal: true

module WildGapMiner
  class Configuration
    DEFAULTS = {
      denial_threshold: 0.2,
      failure_threshold: 0.15,
      latency_p95_threshold_ms: 500.0,
      utilization_min_count: 5,
      coverage_min_fraction: 0.3,
      pattern_min_occurrences: 3,
      max_gaps_per_type: 50
    }.freeze

    DEFAULT_SEVERITY_WEIGHTS = {
      denial: 1.0,
      failure: 1.0,
      latency: 1.0,
      utilization: 1.0,
      coverage: 1.0,
      pattern: 1.0
    }.freeze

    attr_reader :denial_threshold,
                :failure_threshold,
                :latency_p95_threshold_ms,
                :utilization_min_count,
                :coverage_min_fraction,
                :pattern_min_occurrences,
                :max_gaps_per_type,
                :severity_weights

    def initialize
      @denial_threshold = DEFAULTS[:denial_threshold]
      @failure_threshold = DEFAULTS[:failure_threshold]
      @latency_p95_threshold_ms = DEFAULTS[:latency_p95_threshold_ms]
      @utilization_min_count = DEFAULTS[:utilization_min_count]
      @coverage_min_fraction = DEFAULTS[:coverage_min_fraction]
      @pattern_min_occurrences = DEFAULTS[:pattern_min_occurrences]
      @max_gaps_per_type = DEFAULTS[:max_gaps_per_type]
      @severity_weights = DEFAULT_SEVERITY_WEIGHTS.dup
    end

    def denial_threshold=(value)
      check_frozen!
      validate_float!(value, :denial_threshold, min: 0.0, max: 1.0)
      @denial_threshold = value.to_f
    end

    def failure_threshold=(value)
      check_frozen!
      validate_float!(value, :failure_threshold, min: 0.0, max: 1.0)
      @failure_threshold = value.to_f
    end

    def latency_p95_threshold_ms=(value)
      check_frozen!
      validate_float!(value, :latency_p95_threshold_ms, min: 0.0)
      @latency_p95_threshold_ms = value.to_f
    end

    def utilization_min_count=(value)
      check_frozen!
      validate_integer!(value, :utilization_min_count, min: 0)
      @utilization_min_count = value.to_i
    end

    def coverage_min_fraction=(value)
      check_frozen!
      validate_float!(value, :coverage_min_fraction, min: 0.0, max: 1.0)
      @coverage_min_fraction = value.to_f
    end

    def pattern_min_occurrences=(value)
      check_frozen!
      validate_integer!(value, :pattern_min_occurrences, min: 1)
      @pattern_min_occurrences = value.to_i
    end

    def max_gaps_per_type=(value)
      check_frozen!
      validate_integer!(value, :max_gaps_per_type, min: 1)
      @max_gaps_per_type = value.to_i
    end

    def severity_weights=(value)
      check_frozen!
      raise ConfigurationError, 'severity_weights must be a Hash' unless value.is_a?(Hash)

      @severity_weights = DEFAULT_SEVERITY_WEIGHTS.merge(value.transform_keys(&:to_sym))
    end

    def freeze!
      @severity_weights.freeze
      freeze
    end

    private

    def check_frozen!
      raise FrozenError, "can't modify frozen #{self.class}" if frozen?
    end

    def validate_float!(value, name, min: nil, max: nil)
      raise ConfigurationError, "#{name} must be numeric" unless value.is_a?(Numeric)
      raise ConfigurationError, "#{name} must be >= #{min}" if min && value < min
      raise ConfigurationError, "#{name} must be <= #{max}" if max && value > max
    end

    def validate_integer!(value, name, min: nil)
      raise ConfigurationError, "#{name} must be an Integer" unless value.is_a?(Integer)
      raise ConfigurationError, "#{name} must be >= #{min}" if min && value < min
    end
  end
end
