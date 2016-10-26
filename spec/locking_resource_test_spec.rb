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

    it 'should log if lock uncontested' do
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

    it 'should log if lock not present' do
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

    it 'should log if lock not present' do
      chef_run.converge(described_recipe)
      expect(chef_run).to serialize_locking_resource('Dummy Resource Lock')
    end
  end
end

describe 'locking_resource_test::simple_serialized_process' do
  require_relative '../libraries/locking_resource.rb'

  context 'default configuration' do
    let :chef_run do
      ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '12.04',
                               cookbook_path: cookbook_path,
                               step_into: ['locking_resource']) do |node|
        node.automatic['fqdn'] = 'test_host'
      end
    end

    it 'should restart if process not restarted since lock' do
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:lock_matches?).and_return(true)
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:process_start_time).and_return(Time.now-5)
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:get_node_ctime).and_return(Time.now)
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:release_lock).and_return(true)
      chef_run.converge(described_recipe)
      expect(chef_run).to run_ruby_block('my resource')
    end


    it 'should not restart if process restarted since lock' do
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:lock_matches?).and_return(true)
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:process_start_time).and_return(Time.now+5)
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:get_node_ctime).and_return(Time.now-15)
      allow_any_instance_of(Chef::Provider::LockingResource).to \
        receive(:release_lock).and_return(true)
      chef_run.converge(described_recipe)
      expect(chef_run).not_to run_ruby_block('my resource')
    end
  end

  context 'verify matcher' do
    let :chef_run do
      ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '12.04',
                               cookbook_path: cookbook_path) do |node|
      end
    end

    it 'should log if lock not present' do
      chef_run.converge(described_recipe)
      expect(chef_run).to serialize_process_locking_resource('Test we run if process dead')
    end
  end
end
