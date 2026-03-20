# frozen_string_literal: true

require_relative 'lib/wild_gap_miner/version'

Gem::Specification.new do |spec|
  spec.name = 'wild-gap-miner'
  spec.version = WildGapMiner::VERSION
  spec.authors = ['Intent Solutions']
  spec.summary = 'Capability gap analysis from telemetry exports'
  spec.description = 'Library for analyzing session telemetry exports to surface ' \
                     'capability gaps, tool issues, and investment opportunities ' \
                     'in AI-assisted development workflows.'
  spec.homepage = 'https://github.com/jeremylongshore/wild-gap-miner'
  spec.license = 'Nonstandard'
  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*.rb', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.metadata['rubygems_mfa_required'] = 'true'
end
