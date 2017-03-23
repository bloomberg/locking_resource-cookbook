include_recipe 'zookeeper::default'
include_recipe 'zookeeper::service'
include_recipe 'locking_resource::default'

log 'This is a dummy resource' do
  action :nothing
end

locking_resource 'Dummy Resource Lock' do
  resource 'log[This is a dummy resource]'
  action :serialize
  perform :write
end
