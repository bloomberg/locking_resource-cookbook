node.default['zookeeper']['service_style'] = 'runit'
include_recipe 'zookeeper::default'
include_recipe 'runit'
include_recipe 'zookeeper::service'
include_recipe 'locking_resource::default'

log 'This is a dummy resource' do
  message 'should see this in output'
  action :nothing
end

locking_resource 'Dummy Resource Lock' do
  resource 'log[This is a dummy resource]'
  action :serialize
  perform :write
end
