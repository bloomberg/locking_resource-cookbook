require 'chefspec'

describe 'locking_resource::default' do
  let :chef_run do
    ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '14.04',
                             cookbook_path: File.join(File.expand_path(Dir.pwd), 'berks-cookbooks'))
  end

  it 'should serialize locking resource' do
    chef_run.converge(described_recipe)
    %w{make patch gcc}.each do|pkg|
      expect(chef_run).to install_package(pkg)
    end
    expect(chef_run).to install_gem_package('zookeeper')
    expect(chef_run).to run_execute('correct-gem-permissions')
    allow(Gem).to receive(:clear_paths) 
    allow(Gem).to receive(:clear_paths).and_return(true)
    allow(Kernel).to receive(:require) 
    allow(Kernel).to receive(:require).with("zookeeper").and_return(true)
  end
end

#execute "correct-gem-permissions" do
#  command "find #{Gem.default_dir()} -type f -exec chmod a+r {} \\; && " +
#          "find #{Gem.default_dir()} -type d -exec chmod a+rx {} \\;"
#  user "root"
#  action :nothing
#end.run_action(:run)
