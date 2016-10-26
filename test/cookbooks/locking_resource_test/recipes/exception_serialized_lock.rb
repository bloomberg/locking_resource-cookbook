node.default['zookeeper']['service_style'] = 'runit'
include_recipe 'zookeeper::default'
include_recipe 'runit'
include_recipe 'zookeeper::service'
include_recipe 'locking_resource::default'
Chef::Recipe.send(:include, LockingResource::Helper)
Chef::Resource::RubyBlock.send(:include, LockingResource::Helper)

###
# This recipe is designed to test the lock is held
# if the serialized action crashes
#

lock_resource = 'Dummy Resource Lock'
lock_path = ::File.join(node[:locking_resource][:restart_lock][:root],
                        "ruby_block[#{lock_resource.gsub(' ', ':')}]")
zk_hosts = parse_zk_hosts(node[:locking_resource][:zookeeper_servers])
node.run_state['times'] = {}

# Create the resource for us to serialize
ruby_block lock_resource do
  block do
    node.run_state['times'][lock_resource] = Time.now
    Chef::Log.warn "Dummy resource ran at: #{node.run_state['times'][lock_resource]}"
    raise "Failing to ensure lock sticks around..."
  end
  action :nothing
end

log 'Initial Time' do
  message lazy{"The time starting is now: #{Time.now}"}
  notifies :run, 'ruby_block[Verify Lock Still Held]', :delayed
end

# Prove that the Chef run is continuing while the release thread sleeps
ruby_block 'Verify Lock Still Held' do
  block do
    res_run_time = node.run_state['times'][lock_resource]
    now = Time.now
    Chef::Log.warn "The time after locking resource: #{now}"
    raise "Locked resource has not run before this! (#{res_run_time} < #{now})" unless res_run_time < now
    raise "Not holding lock!" unless lock_matches?(zk_hosts, lock_path, node[:fqdn])
    (0...10).each do
      Chef::Log.warn("ALL CHECKS PASSED!")
    end
  end
  action :nothing
end

# Try to run a serialized action
locking_resource "ruby_block[#{lock_resource}]" do
  resource "ruby_block[#{lock_resource}]"
  perform :run
  action :serialize
end
