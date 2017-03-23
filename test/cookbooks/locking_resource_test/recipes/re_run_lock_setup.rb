include_recipe 'zookeeper::default'
include_recipe 'zookeeper::service'
include_recipe 'locking_resource::default'
Chef::Recipe.send(:include, LockingResource::Helper)
Chef::Resource::RubyBlock.send(:include, LockingResource::Helper)

###
# This recipe is designed to create a held lock and ensure we
# don't run due to the lock (used by recipes to test handling once
# lock released). Process:
# * Create conflicting lock
# * Run a serialized process action (should timeout)
# * Run a serialized process action (should timeout again)
# * Clear conflicting lock
#

# Reset failed_locks
node.normal['locking_resource']['failed_locks'] = {}

zk_hosts = parse_zk_hosts(node['locking_resource']['zookeeper_servers'])
lock_resource = 'Dummy Resource One'
lock_path = "ruby_block[#{lock_resource.tr(' ', ':')}]"
full_lock_path = ::File.join(node['locking_resource']['restart_lock']['root'],
                             lock_path)
node.run_state['locking_resource_test'] = {}
node.run_state['locking_resource_test']['ran_action'] = false

# Create the resources for us to serialize
ruby_block lock_resource do
  block do
    Chef::Log.warn "Dummy resource -- which should run -- ran at: #{Time.now}"
    node.run_state['locking_resource_test']['ran_action'] = true
  end
  action :nothing
end

ruby_block 'Create a blocking lock' do
  block do
    create_node(zk_hosts, full_lock_path, 'foobar') and \
      Chef::Log.warn "#{Time.now}: Acquired blocking lock"
    raise 'Did not set lock' unless lock_matches?(zk_hosts, full_lock_path,
                                                  'foobar')
  end
end

# Try to run a serialized action -- timeout
locking_resource 'Test we do not run with held lock -- should timeout' do
  lock_name lock_path
  resource "ruby_block[#{lock_resource}]"
  perform :run
  action :serialize
  ignore_failure true
end

ruby_block 'Verify rerun state set' do
  block do
    raise 'Some how already ran' if \
      node.run_state['locking_resource_test']['ran_action']
    re_run_parent = node['locking_resource']['failed_locks']
    raise "Re-run state not set #{re_run_parent}" unless \
      re_run_parent.key?(full_lock_path)
  end
end

# Still should not run the serialized action -- but verify we increment state
# and ensure we don't run without the lock
locking_resource 'ruby_block -- timeout again' do
  lock_name lock_path
  resource "ruby_block[#{lock_resource}]"
  perform :run
  action :serialize
  ignore_failure true
end

ruby_block 'Verify rerun failures incremented' do
  block do
    raise 'Some how already ran' if \
      node.run_state['locking_resource_test']['ran_action']
    fails = node['locking_resource']['failed_locks'][full_lock_path]['fails']
    raise "Re-run state not incremented: #{fails}" unless fails == 2
  end
end

ruby_block 'Clean-up the stale lock' do
  block do
    raise 'Some how already ran' if \
      node.run_state['locking_resource_test']['ran_action']
    release_lock(zk_hosts, full_lock_path, 'foobar')
    raise 'Did not release lock' if lock_matches?(zk_hosts, full_lock_path,
                                                  'foobar')
  end
end
