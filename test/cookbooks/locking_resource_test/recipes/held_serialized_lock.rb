include_recipe 'zookeeper::default'
include_recipe 'zookeeper::service'
include_recipe 'locking_resource::default'
Chef::Recipe.send(:include, LockingResource::Helper)
Chef::Resource::RubyBlock.send(:include, LockingResource::Helper)

###
# This recipe is designed to create a competiting lock and ensure we
# block until that lock is released
#

lock_resource = 'Dummy Resource Lock'
colliding_lock_data = 'This is arbitrary data'
lock_path = ::File.join(node['locking_resource']['restart_lock']['root'],
                        "ruby_block[#{lock_resource.tr(' ', ':')}]")
zk_hosts = parse_zk_hosts(node['locking_resource']['zookeeper_servers'])
node.run_state['thread_hdl'] = nil
node.run_state['times'] = {}
# Let us timeout much quicker for the sake of testing
override_timeout = 5

# Create the resource for us to serialize
ruby_block lock_resource do
  block do
    node.run_state['times'][lock_resource] = Time.now
    Chef::Log.warn 'Dummy resource ran at: ' +
                   node.run_state['times'][lock_resource].to_s
  end
  action :nothing
end

# Create the blocking lock
ruby_block 'Create a Colliding Lock' do
  block do
    got_lock = false
    start_time = node.run_state['times']['acquired_colliding_lock'] = Time.now
    lock_acquire_timeout =
      node['locking_resource']['restart_lock_acquire']['timeout']
    while !got_lock && (start_time + lock_acquire_timeout) >= Time.now
      got_lock = create_node(zk_hosts, lock_path, colliding_lock_data) and \
        Chef::Log.warn "#{start_time}: Acquired colliding lock"
      sleep(0.25)
    end
  end
end

log 'Initial Time' do
  message lazy { "The time starting is now: #{Time.now}" }
end

# Release the blocking lock after a sleep time
ruby_block 'Run Locking Resource and Unwind Colliding Lock' do
  block do
    # create a thread to release the lock sometime in the future
    require 'thread'
    node.run_state['thread_hdl'] = Thread.new do
      begin
        node.run_state['times']['unwind_sleep_time'] = Time.now
        Chef::Log.warn \
          "#{node.run_state['times']['unwind_sleep_time']}: Sleeping"

        # sleep all but 2 seconds of the default timeout
        sleep(override_timeout - 2)

        # release lock
        node.run_state['times']['unwind_wake_time'] = Time.now
        release_lock(zk_hosts, lock_path, colliding_lock_data) and \
          Chef::Log.warn \
            "#{node.run_state['times']['unwind_wake_time']}: " \
            'Released colliding lock'
      rescue ThreadError
        raise
      end
    end
  end
end

# Prove that the Chef run is continuing while the release thread sleeps
ruby_block 'Time before locking resource' do
  block do
    node.run_state['times']['before_locking_resource'] = Time.now
    Chef::Log.warn 'The time before locking resource: ' +
                   node.run_state['times']['before_locking_resource'].to_s
  end
end

# Try to run a serialized action
locking_resource "ruby_block[#{lock_resource}]" do
  resource "ruby_block[#{lock_resource}]"
  perform :run
  timeout override_timeout
  action :serialize
end

# Report the time after the serialized action ran
ruby_block 'Time after locking resource' do
  block do
    node.run_state['times']['after_locking_resource'] = Time.now
    Chef::Log.warn 'Time after locking resource (should be ' \
                   "#{override_timeout - 2} " \
                   'seconds after last print) ' +
                   node.run_state['times']['after_locking_resource'].to_s

    # ensure the sleep thread has cleaned up
    node.run_state['thread_hdl'].join
  end
end

# Make sure we actually waiting for the lock to release
ruby_block 'verify timings' do
  block do
    # verify the Chef run progressed while we waited to release the lock
    if node.run_state['times']['before_locking_resource'].to_f > \
       node.run_state['times']['unwind_wake_time'].to_f
      raise('Chef run should have continued ' \
        "(#{node.run_state['times']['before_locking_resource']}) before lock " \
        "release thread awoke (#{node.run_state['times']['unwind_wake_time']})")
    end

    # verify the serialized resource only ran after the lock was released
    if node.run_state['times']['unwind_wake_time'].to_f > \
       node.run_state['times'][lock_resource].to_f
      raise('Locking resource should run ' \
        "(#{node.run_state['times'][lock_resource]}) only after we unwind the" \
        " colliding lock (#{node.run_state['times']['unwind_wake_time']})")
    end
  end
end
