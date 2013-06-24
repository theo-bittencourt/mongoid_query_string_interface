begin
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
  end
  SimpleCov.coverage_dir 'coverage'
rescue LoadError
  # ignore simplecov in ruby < 1.9
end

begin
  require 'bundler/setup'
  Bundler.require(:default, :development)
rescue LoadError
  puts 'Bundler is not installed, you need to gem install it in order to run the specs.'
  exit 1
end

require 'mongoid'
require 'will_paginate/collection'

Mongoid.load!(File.expand_path('../mongoid.yml', File.dirname(__FILE__)), :test)

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir[File.expand_path('support/**/*.rb', File.dirname(__FILE__))].each { |f| require f }

# Requires lib.
Dir[File.expand_path('../lib/**/*.rb', File.dirname(__FILE__))].each { |f| require f }

RSpec.configure do |config|
  config.filter_run wip: true
  config.run_all_when_everything_filtered = true
  config.mock_with :rspec

  # http://adventuresincoding.com/2012/05/how-to-configure-cucumber-and-rspec-to-work-with-mongoid-30
  config.before(:each) { Mongoid.purge! }
end
