include_recipe 'zookeeper::default'
include_recipe 'zookeeper::service'
include_recipe 'locking_resource::default'
include_recipe 'locking_resource_test::re_run_lock_setup'
Chef::Recipe.send(:include, LockingResource::Helper)
Chef::Resource::RubyBlock.send(:include, LockingResource::Helper)

###
# This recipe is designed to run after re_run_lock_setup has created state
# for resource failure
# * Run a serialized process action with newer process running
#   (should not execute -- but should clean-up state)
#

lock_resource = 'Dummy Resource One'
lock_path = "ruby_block[#{lock_resource.gsub(' ', ':')}]"
full_lock_path = ::File.join(node[:locking_resource][:restart_lock][:root],
                             lock_path)
test_process = '/bin/sleep 60'                                                  
                                                                                
ruby_block 'Run a test process' do                                              
  block do                                                                      
    # make sure we wait long enough that at a one second granularity the        
    # state times and process start times are different                         
    sleep(2)                                                                    
    node.run_state[:child_pid] = spawn(test_process)                            
  end                                                                           
end  

locking_resource 'Clean-up state (and not run) if process newer than lock' do
  lock_name lock_path
  resource "ruby_block[#{lock_resource}]"
  process_pattern do
    command_string test_process
    full_cmd true
  end
  action :serialize_process
  perform :run
end

ruby_block 'Check action not run and re-run state was cleaned up' do
  block do
    raise 'Ran action and should not have!' if \
      node.run_state[:locking_resource_test][:ran_action]
    re_run_state = node[:locking_resource][:failed_locks][full_lock_path]
    raise "Re-run state not cleaned up: #{re_run_state}" if re_run_state
  end
end
