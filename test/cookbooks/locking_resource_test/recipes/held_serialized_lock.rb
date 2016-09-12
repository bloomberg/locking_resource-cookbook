node.default['zookeeper']['service_style'] = 'runit'
include_recipe 'zookeeper::default'
include_recipe 'runit'
include_recipe 'zookeeper::service'
include_recipe 'locking_resource::default'
Chef::Resource::RubyBlock.send(:include, Locking_Resource::Helper)

log 'This is a dummy resource' do
  message 'should not see this in output'
  action :nothing
end

lock_resource = 'Dummy Resource Lock'

ruby_block 'Create a Lock Collision' do
  block do
    lock_path = ::File.join(node[:locking_resource][:restart_lock][:root],
                  lock_resource.gsub(' ', ':'))
    got_lock = create_node(parse_zk_hosts(node[:locking_resource][:zookeeper_servers]),
                 lock_path, node[:fqdn]) and \
                 Chef::Log.info 'Acquired colliding lock'
  end
end

locking_resource lock_resource do
  resource 'log[This is a dummy resource]'
  action :serialize
  perform :write
end
