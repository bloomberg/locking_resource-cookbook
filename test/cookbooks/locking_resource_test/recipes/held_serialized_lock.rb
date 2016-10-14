node.default['zookeeper']['service_style'] = 'runit'
include_recipe 'zookeeper::default'
include_recipe 'runit'
include_recipe 'zookeeper::service'
include_recipe 'locking_resource::default'
Chef::Recipe.send(:include, LockingResource::Helper)
Chef::Resource::RubyBlock.send(:include, LockingResource::Helper)

lock_resource = 'Dummy Resource Lock'
lock_path = ::File.join(node[:locking_resource][:restart_lock][:root],
              lock_resource.gsub(' ', ':'))
zk_hosts = parse_zk_hosts(node[:locking_resource][:zookeeper_servers])
@thread_hdl = nil

log 'Initial Time' do
  message lazy{"The time starting is now: #{Time.now}"}
end

log 'This is a dummy resource' do
  message lazy{"The time after locking now: #{Time.now}"}
  action :nothing
end

ruby_block 'Create a Lock Collision' do
  block do
    got_lock = false
    start_time = Time.now
    lock_acquire_timeout = node[:locking_resource][:restart_lock_acquire][:timeout]
    while !got_lock && (start_time + lock_acquire_timeout) >= Time.now
      got_lock = create_node(zk_hosts, lock_path, node[:fqdn]) and \
            Chef::Log.info "#{Time.now}: Acquired colliding lock"
      sleep(0.25)
    end
  end
end

ruby_block 'Undo Lock Collision Background Thread' do
  block do
    require 'thread'
    @thread_hdl = Thread.new do
      begin
        # sleep all but 10 seconds of the default timeout
        puts "XXX Sleeping"
        sleep(node[:locking_resource][:restart_lock_acquire][:timeout] - 5)
        puts "XXX Done Sleeping: #{lock_path}"
        puts "XXX data1: #{get_node_data(zk_hosts, lock_path)}"
        puts "XXX data2: #{get_node_data(zk_hosts, '/lock/Dummy:Resource:Lock')}"
        got_lock = release_lock(zk_hosts, lock_path, node[:fqdn]) and \
                     Chef::Log.info "#{Time.now}: Released colliding lock"
        puts "XXX data: #{get_node_data(zk_hosts, lock_path)}"
      rescue ThreadError => e
        raise
      end
    end
    @thread_hdl.run
  end
end

log 'Time during sleep' do
  message lazy{"The time should be during sleep: #{Time.now}"}
end

locking_resource lock_resource do
  resource 'log[This is a dummy resource]'
  action :serialize
  perform :write
end

log 'Time after sleep' do
  message lazy{"Time after sleep (should be " \
    "#{node[:locking_resource][:restart_lock_acquire][:timeout] - 5}" \
    "seconds after last print) #{Time.now}"}
end

