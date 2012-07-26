# -*- mode: ruby; encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = 'right_link'
  s.version     = '5.9.0'
  s.platform    = Gem::Platform::RUBY
  
  s.authors     = ['RightScale']
  s.email       = 'support@rightscale.com'
  s.homepage    = 'https://github.com/rightscale/right_link'
  s.summary     = %q{Reusable foundation code.}
  s.description = %q{A toolkit of useful, reusable foundation code created by RightScale.}
  
  s.required_rubygems_version = '>= 1.3.7'

  s.add_runtime_dependency('right_agent', ['~> 0.10'])
  s.add_runtime_dependency('right_scraper', ['~> 3.0'])
  s.add_runtime_dependency('right_popen', ['~> 1.0'])
  s.add_runtime_dependency('right_http_connection', ['~> 1.3'])
  s.add_runtime_dependency('right_support', ['~> 2.0'])

  s.add_runtime_dependency('chef', ['>= 0.10.10'])
  s.add_runtime_dependency('encryptor', ['~> 1.1'])

  s.files = Dir.glob('Gemfile') +
            Dir.glob('Gemfile.lock') +
            Dir.glob('init/*') +
            Dir.glob('actors/*.rb') +
            Dir.glob('bin/*.rb') +
            Dir.glob('bin/*.sh') +
            Dir.glob('lib/**/*.rb') +
            Dir.glob('lib/**/*.pub') +
            Dir.glob('scripts/*') +
            Dir.glob('lib/instance/cook/*.crt')
end
