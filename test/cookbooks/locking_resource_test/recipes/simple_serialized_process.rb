include_recipe 'zookeeper::default'
include_recipe 'zookeeper::service'
include_recipe 'locking_resource::default'

lock_resource = 'my resource'
node.run_state['ran_action'] = false

ruby_block lock_resource do
  block do
    Chef::Log.warn 'Dummy resource -- which should run'
    node.run_state['ran_action'] = true
  end
  action :nothing
end

locking_resource 'Test we run if process dead' do
  resource "ruby_block[#{lock_resource}]"
  process_pattern do
    command_string 'not a command'
  end
  action :serialize_process
  perform :run
end

# Make sure we actually logged
ruby_block 'verify dummy resource actually ran' do
  block do
    # verify the Chef ran the action
    raise("Chef was supposed to run ruby_block[#{lock_resource}]") unless
      node.run_state['ran_action']
  end
end
