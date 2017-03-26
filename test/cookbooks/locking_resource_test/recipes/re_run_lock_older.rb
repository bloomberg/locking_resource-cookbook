include_recipe 'zookeeper::default'
include_recipe 'zookeeper::service'
include_recipe 'locking_resource::default'
include_recipe 'locking_resource_test::re_run_lock_setup'
Chef::Recipe.send(:include, LockingResource::Helper)
Chef::Resource::RubyBlock.send(:include, LockingResource::Helper)

####                                                                             
## This recipe is designed to run after re_run_lock_setup has created state      
## for resource failure                                                          
## * Run a serialized process action with old process running (should execute)       
##  

lock_resource = 'Dummy Resource One'
lock_path = "ruby_block[#{lock_resource.gsub(' ', ':')}]"
full_lock_path = ::File.join(node[:locking_resource][:restart_lock][:root],
                             lock_path)

locking_resource 'We run if process older than first attempt' do
  lock_name lock_path
  resource "ruby_block[#{lock_resource}]"
  process_pattern do
    command_string 'init'
    user 'root'
  end
  action :serialize_process
  perform :run
end

ruby_block 'Check re-run state was cleaned up' do
  block do
    raise 'Did not run action!' unless \
      node.run_state[:locking_resource_test][:ran_action]
    re_run_state = node[:locking_resource][:failed_locks][full_lock_path]
    raise "Re-run state not cleaned up: #{re_run_state}" if re_run_state
  end
end
