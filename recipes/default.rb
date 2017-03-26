#
# Cookbook Name:: locking_resource
# Recipe:: default
#
# Copyright 2016, Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# ensure the Zookeeper Gem is available for use in later recipes
# it seems chef_gem fails to use the embedded gem(1) binary so use gem_package
# and a hack to use rubygems to find the current Ruby binary;
# assume gem is in the same dir (valid for Chef 10, Chef 11 dpkg and
# Chef 11 Omnibus)
require 'pathname'
require 'rubygems'
gem_path = Pathname.new(Gem.ruby).dirname.join('gem').to_s

# build requirements for zookeeper
%w(make patch gcc).each do |pkg|
  package pkg do
    action :nothing
  end.run_action(:install)
end

gem_package 'zookeeper' do
  gem_binary gem_path
  version '>0.0'
  action :nothing
end.run_action(:install)

# work around funky umasks
execute 'correct-gem-permissions' do
  command "find #{Gem.default_dir} -type f -exec chmod a+r {} \\; && " \
          "find #{Gem.default_dir} -type d -exec chmod a+rx {} \\;"
  user 'root'
  action :nothing
end.run_action(:run)

Gem.clear_paths
require 'zookeeper'
