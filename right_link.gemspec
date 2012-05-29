# -*- mode: ruby; encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name        = "right_link"
  s.version     = '0.3'
  s.platform    = Gem::Platform::RUBY
  
  s.authors     = ['RightScale']
  s.email       = 'support@rightscale.com'
  s.homepage    = 'https://github.com/rightscale/right_link'
  s.summary     = %q{Reusable foundation code.}
  s.description = %q{A toolkit of useful, reusable foundation code created by RightScale.}
  
  s.required_rubygems_version = ">= 1.3.7"
  
  s.files = Dir.glob('Gemfile') +
            Dir.glob('Gemfile.lock') +
            Dir.glob('init/*') +
            Dir.glob('actors/*.rb') +
            Dir.glob('bin/*.rb') +
            Dir.glob('bin/*.sh') +
            Dir.glob('lib/**/*.rb') +
            Dir.glob('scripts/*') +
            Dir.glob('lib/instance/cook/*.crt')
end
