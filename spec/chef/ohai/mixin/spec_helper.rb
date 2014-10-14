require File.expand_path('../../../spec_helper', __FILE__)

shared_examples_for '!windows env' do
  before(:each) do
    @old_RUBY_PLATFORM = RUBY_PLATFORM
    Object.const_set('RUBY_PLATFORM', 'x86_64-darwin13.0.0')
  end

  after(:each) do
    Object.const_set('RUBY_PLATFORM', @old_RUBY_PLATFORM)
  end
end

shared_examples_for 'windows env' do
  before(:each) do
    @old_RUBY_PLATFORM = RUBY_PLATFORM
    Object.const_set('RUBY_PLATFORM', 'mswin')
  end

  after(:each) do
    Object.const_set('RUBY_PLATFORM', @old_RUBY_PLATFORM)
  end
end
