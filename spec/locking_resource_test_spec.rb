require 'chefspec'

cookbook_path = File.join(File.expand_path(Dir.pwd), 'berks-cookbooks')

describe 'locking_resource_test::simple_serialized_lock' do
  require_relative '../libraries/locking_resource.rb'

  context 'default configuration' do
    let :chef_run do
      ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '12.04',
                               cookbook_path: cookbook_path,
                               step_into: ['locking_resource']) do |node|
        node.automatic['fqdn'] = 'test_host'
      end
    end

    it "should log if lock uncontested" do
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:lock_matches?)
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:lock_matches?).and_return(false)
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:create_node) 
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:create_node).and_return(true)
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:release_lock).and_return(true)
      chef_run.converge(described_recipe)
      expect(chef_run).to write_log('This is a dummy resource')
    end

  end

  context 'locking disabled' do
    let :chef_run do
      ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '12.04',
                               cookbook_path: cookbook_path,
                               step_into: ['locking_resource']) do |node|
        node.normal['locking_resource']['skip_restart_coordination'] = true
      end
    end

    it "should log if lock not present" do
      chef_run.converge(described_recipe)
      expect(chef_run).to write_log('This is a dummy resource')
    end
  end

  context 'verify matcher' do
    let :chef_run do
      ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '12.04',
                               cookbook_path: cookbook_path) do |node|
      end
    end

    it "should log if lock not present" do
      chef_run.converge(described_recipe)
      expect(chef_run).to serialize_locking_resource('Dummy Resource Lock')
      expect(chef_run).to not write_log('This is a dummy resource')
    end
  end
end
