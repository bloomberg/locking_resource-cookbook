require 'chefspec'

describe 'locking_resource_test::simple_serialized_lock' do
  let :chef_run do
    ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '12.04',
                             step_into: ['locking_resource'])
  end

  it "should log if lock not present" do
    allow(::LockingResource::Helper).to receive(:lock_matches?) 
    allow(::LockingResource::Helper).to receive(:lock_matches?).and_return(false)
    allow(::LockingResource::Helper).to receive(:create_node) 
    allow(::LockingResource::Helper).to receive(:create_node).and_return(true)
    chef_run.converge(described_recipe)
    expect(chef_run).to write_log('zookeeper')
  end
end
