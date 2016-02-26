# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'subconv/version'

Gem::Specification.new do |s|
  s.name = 'subconv'
  s.version = Subconv::VERSION

  s.required_rubygems_version = Gem::Requirement.new('>= 0') if s.respond_to? :required_rubygems_version=
  s.required_ruby_version = '>= 2.0'
  s.authors = ['Philipp Kerling']
  s.email = ['pkerling@casix.org']
  s.homepage = 'https://github.com/pkerling/subconv'
  s.files = `git ls-files -z`.split("\x0").reject { |elem| elem =~ %r{^scc-data/} }
  s.executables = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ['lib']
  s.license = 'MIT'

  s.rdoc_options = ['--charset=UTF-8']
  s.require_paths = ['lib']

  s.rubygems_version = '1.3.7'
  s.summary = 'Subtitle conversion (SCC to WebVTT)'
  s.add_dependency 'solid-struct'
  s.add_dependency 'timecode'
  s.add_development_dependency 'bundler', '~> 1.7'
  s.add_development_dependency 'rspec', '~> 3.4.0'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'rubocop'
  s.add_development_dependency 'json'
  s.add_development_dependency 'coveralls'
end
