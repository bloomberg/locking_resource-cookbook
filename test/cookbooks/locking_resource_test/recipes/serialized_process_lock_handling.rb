include_recipe 'zookeeper::default'
include_recipe 'zookeeper::service'
include_recipe 'locking_resource::default'
Chef::Recipe.send(:include, LockingResource::Helper)
Chef::Resource::RubyBlock.send(:include, LockingResource::Helper)

###
# This recipe is designed to create a held lock and ensure we
# re-run due to the lock
#

zk_hosts = parse_zk_hosts(node[:locking_resource][:zookeeper_servers])
lock_resource1 = 'Dummy Resource One'
lock_resource2 = 'Dummy Resource Two'
lock_path1 = ::File.join(node[:locking_resource][:restart_lock][:root],
                        "ruby_block[#{lock_resource1.gsub(' ', ':')}]")
lock_path2 = ::File.join(node[:locking_resource][:restart_lock][:root],
                        "ruby_block[#{lock_resource2.gsub(' ', ':')}]")
node.run_state[:locking_resource] = {}
node.run_state[:locking_resource][:ran_action] = []
node.run_state[:locking_resource][:ran_action][1] = false
node.run_state[:locking_resource][:ran_action][2] = false

# Create the resources for us to serialize
ruby_block lock_resource1 do
  block do
    Chef::Log.warn "Dummy resource -- which should run -- ran at: #{Time.now}"
    node.run_state[:locking_resource][:ran_action][1] = true
  end
  action :nothing
end

ruby_block lock_resource2 do
  block do
    Chef::Log.warn "Dummy resource -- which should not run -- ran at: #{Time.now}"
    node.run_state[:locking_resource][:ran_action][2] = true
  end
  action :nothing
end

# Create a stale lock
ruby_block 'Create a stale lock for init process' do
  block do
    got_lock = create_node(zk_hosts, lock_path1, node[:fqdn]) and \
        Chef::Log.warn "#{Time.now}: Acquired stale lock"
    raise "Did not set lock" unless lock_matches?(zk_hosts, lock_path1,
                                                  node[:fqdn])
  end
end

# Try to run a serialized action
locking_resource "ruby_block[#{lock_resource1}]" do
  resource "ruby_block[#{lock_resource1}]"
  process_pattern {command_string 'init'
                   user 'root'}
  perform :run
  action :serialize_process
end

# Make sure we actually waiting for the lock to release
ruby_block 'verify lock cleaned-up for init process' do
  block do
    raise 'Did not clean-up lock' if lock_matches?(zk_hosts, lock_path1,
                                                   node[:fqdn])
    # verify the Chef ran the action
    raise("Chef did not run ruby_block[#{lock_resource}]") unless
      node.run_state[:locking_resource][:ran_action][1]
  end
end

# Create a stale lock and run a process after
ruby_block 'Create a stale lock and run a command' do
  block do
    got_lock = create_node(zk_hosts, lock_path2, node[:fqdn]) and \
        Chef::Log.warn "#{Time.now}: Acquired stale lock"
    raise "Did not set lock" unless lock_matches?(zk_hosts, lock_path2,
                                                  node[:fqdn])
    # make sure we wait long enough that at a one second granularity the znode
    # and process start times are different
    sleep(2)
    node.run_state[:child_pid] = spawn("/bin/sleep 60")
  end
end

# Try to run a serialized action
locking_resource "ruby_block[#{lock_resource2}]" do
  resource "ruby_block[#{lock_resource2}]"
  process_pattern {command_string 'sleep 60'
                   user Process.uid.to_s
                   full_cmd true}
  perform :run
  action :serialize_process
end

# Make sure we actually waiting for the lock to release
ruby_block 'verify lock cleaned-up for recently run command' do
  block do
    raise 'Did not clean-up lock' if lock_matches?(zk_hosts, lock_path2,
                                              node[:fqdn])
    # verify the Chef ran the action
    raise("Chef ran ruby_block[#{lock_resource2}]") if
      node.run_state[:locking_resource][:ran_action][2]

    Process.kill("TERM", node.run_state[:child_pid])
  end
end
