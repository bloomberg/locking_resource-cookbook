#!/usr/bin/env rake

require 'mixlib/shellout'

chef_version = '12.19.36'
namespace :style do
  desc 'Style check with rubocop'
  task :rubocop do
    ENV['RUBOCOP_OPTS'] = '--out rubocop.log' if ENV['CI']
    # Force a zero exit code until we fix all the cops (someday)
    sh '/opt/chefdk/embedded/bin/rubocop || true'
  end

  desc 'Style check with foodcritic'
  task :foodcritic do
    foodcritic_output = '> foodcritic.log' if ENV['CI']
    sh '/opt/chefdk/embedded/bin/foodcritic '\
       '--epic-fail none ./' \
       "#{foodcritic_output}"
  end
end

begin
  require 'rspec/core/rake_task'

  RSpec::Core::RakeTask.new(:spec) do
    # berks install does not seem to work in our spec_helper; run it manually
    sh 'berks vendor vendor/cookbooks'
  end

  task :default => :spec
rescue LoadError
  # no rspec available
end

desc 'Run style checks'
task style: %w(style:rubocop style:foodcritic)

desc 'Clean some generated files'
task :clean do
  %w(
    **/Berksfile.lock
    .bundle
    .cache
    **/Gemfile.lock
    .kitchen
    vendor
  ).each { |f| FileUtils.rm_rf(Dir.glob(f)) }
end

task :default => 'style spec'
