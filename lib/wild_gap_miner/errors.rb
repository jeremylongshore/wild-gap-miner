# frozen_string_literal: true

module WildGapMiner
  class Error < StandardError; end
  class ParseError < Error; end
  class ValidationError < Error; end
  class SchemaError < Error; end
  class ConfigurationError < Error; end
  class ExportError < Error; end
end
