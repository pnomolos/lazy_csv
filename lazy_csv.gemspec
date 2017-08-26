# -*- encoding: utf-8 -*-
require File.expand_path('../lib/lazy_csv/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Philip Schalm", "Tilo Sloboda"]
  gem.email         = ["pnomolos@gmail.com"]
  gem.description   = %q{Ruby Gem for lazy loading of CSV Files with optional features for embedded comments, unusual field- and record-separators, flexible mapping of CSV-headers to Hash-keys}
  gem.summary       = %q{Ruby Gem for lazy importing of CSV Files (and CSV-like files), with lots of optional features}
  gem.homepage      = "https://github.com/pnomolos/lazy_csv"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "lazy_csv"
  gem.require_paths = ["lib"]
  gem.requirements  = ['csv'] # for CSV.parse() only needed in case we have quoted fields
  gem.version       = LazyCSV::VERSION
  gem.licenses      = ['MIT', 'GPL-2']
  gem.add_development_dependency "rspec"
  # gem.add_development_dependency "guard-rspec"
end
