require 'simplecov'
require 'chefspec'
require 'chefspec/berkshelf'

# We call out to log in the code,
# let us have a mock handy
unless defined?(Log)
  require 'mixlib/log'
  class Log
    extend Mixlib::Log
  end
end

formatters = [SimpleCov::Formatter::HTMLFormatter]

begin
  require 'simplecov-json'
  formatters.push(SimpleCov::Formatter::JSONFormatter)
rescue LoadError
end

begin
  require 'simplecov-rcov'
  formatters.push(SimpleCov::Formatter::RcovFormatter)
rescue LoadError
end

SimpleCov.formatters = formatters
SimpleCov.start

# Require all our libraries
Dir['libraries/*.rb'].each { |f| require File.expand_path(f) }

RSpec.configuration do |config|
  config.color = true
  config.alias_example_group_to :describe_recipe, type: :recipe

  Kernel.srand config.seed
  config.order = :random

  # run as though rspec --format documentation when passing a single spec file
  config.default_formatter = 'doc' if config.files_to_run.one?

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  cookbook_path = File.join(File.expand_path(Dir.pwd), 'vendor/cookbooks')
  berksfile = Berkshelf::Berksfile.from_file('Berksfile')
  berksfile.install(path: cookbook_path, only: 'integration')
end

at_exit do
  ChefSpec::Coverage.report!
end
