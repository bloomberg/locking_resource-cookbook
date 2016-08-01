module Locking_Resource
  module Helper

    include Chef::Mixin::ShellOut
   
    #
    # Restarting of hadoop processes need to be controlled in a way that all
    # the nodes are not down at the sametime, the consequence of which will
    # impact users. In order to achieve this, nodes need to acquire a lock
    # before restarting the process of interest. This function is to acquire
    # the lock which is a znode in zookeeper. The znode name is the name  
    # of the service to be restarted for e.g "hadoop-hdfs-datanode" and is
    # located by default at "/". The imput parameters are service name along
    # with the ZK path (znode name), string of zookeeper servers
    # ("zk_host1:port,sk_host2:port"), and the fqdn of the node acquiring the
    # lock
    # Return value : true or false
    #
    def acquire_restart_lock(znode_path, zk_hosts="localhost:2181", node_name)
      require 'zookeeper'
      lock_acquired = false
      zk = nil
      begin
        zk = Zookeeper.new(zk_hosts)
        if !zk.connected?
          raise "acquire_restart_lock : unable to connect to ZooKeeper quorum "
                "#{zk_hosts}"
        end
        ret = zk.create(:path => znode_path, :data => node_name)
        if ret[:rc] == 0
          lock_acquired = true
        end
      rescue Exception => e
        puts e.message
      ensure
        if !zk.nil?
          zk.close unless zk.closed? 
        end
      end
      return lock_acquired
    end

    #
    # This function is to check whether the lock to restart a particular
    # service is held by a node. The input parameters are the path to the
    # znode used to restart a hadoop service, a string containing the 
    # host port values of the ZooKeeper nodes "host1:port, host2:port" and
    # the fqdn of the host
    # Return value : true or false
    #
    def my_restart_lock?(znode_path,zk_hosts="localhost:2181",node_name)
      require 'zookeeper'
      my_lock = false
      zk = nil
      begin
        zk = Zookeeper.new(zk_hosts)
        if !zk.connected?
          raise "my_restart_lock?: unable to connect to ZooKeeper quorum " \
                "#{zk_hosts}"
        end
        ret = zk.get(:path => znode_path)
        val = ret[:data]
        if val == node_name
          my_lock = true
        end
      rescue Exception => e
        puts e.message
      ensure
        if !zk.nil?
          zk.close unless zk.closed?
        end
      end
      return my_lock
    end

    #
    # Function to release the lock held by the node to restart a particular
    # hadoop service. The input parameters are the name of the path to znode
    # which was used to lock for restarting service, string containing the
    # zookeeper host and port ("host1:port,host2:port") and the fqdn of the
    # node trying to release the lock.
    # Return value : true or false based on whether the lock release was
    #                successful or not
    #
    def rel_restart_lock(znode_path, zk_hosts="localhost:2181",node_name)
      require 'zookeeper'
      lock_released = false
      zk = nil
      begin
        zk = Zookeeper.new(zk_hosts)
        if !zk.connected?
          raise "rel_restart_lock : unable to connect to ZooKeeper quorum " \
                "#{zk_hosts}"
        end
        if my_restart_lock?(znode_path, zk_hosts, node_name)
          ret = zk.delete(:path => znode_path)
        else
          raise "rel_restart_lock : node who is not the owner is trying to "
                "release the lock"
        end
        if ret[:rc] == 0
          lock_released = true
        end
      rescue Exception => e
        puts e.message
      ensure
        if !zk.nil?
          zk.close unless zk.closed? 
        end
      end
      return lock_released
    end

    #
    # Function to get the node name which is holding a particular service
    # restart lock
    # Input parameters: The path to the znode (lock) and the string of
    #                   zookeeper hosts:port 
    # Return value    : The fqdn of the node which created the znode to
    #                   restart or nil
    #
    def get_restart_lock_holder(znode_path, zk_hosts="localhost:2181")
      require 'zookeeper'
      begin
        zk = Zookeeper.new(zk_hosts)
        if !zk.connected?
          raise "get_restart_lock_holder : unable to connect to ZooKeeper " \
                "quorum #{zk_hosts}"
        end
        ret = zk.get(:path => znode_path)
        if ret[:rc] == 0
          val = ret[:data]
        end
      rescue Exception => e
        puts e.message
      ensure
        if !zk.nil?
          zk.close unless zk.closed?
        end
      end
      return val
    end

    #
    # Function to generate the full path of znode which will be used to create
    # a restart lock znode
    # Input paramaters: The path in ZK where znodes are created for the restart
    #                   locks and the lock name
    # Return value    : Fully formed path which can be used to create the znode 
    #
    def format_restart_lock_path(root, lock_name)
      begin
        if root.nil?
          return "/#{lock_name}"
        elsif root == "/"
          return "/#{lock_name}"
        else
          return "#{root}/#{lock_name}"
        end
    end

    #
    # Function to identify start time of a process
    # Input: process_identifier - "pgrep -f" compatible process search string
    # Returns: A Ruby Time object representing the processes start time or nil
    # Note:
    # * If multiple instances are returned from pgrep(1), the time returned
    #   will be the earliest time of all the instances
    # * If the process can not be found, nil is returned
    #
    def process_start_time(process_identifier)
      require 'time'
      begin
        cmd = shell_out!("pgrep -f \"#{process_identifier}\"",
                                        {:returns => [0, 1]})
        # raise for any error
        raise cmd.stderr if !cmd.stderr.empty?

        if cmd.stdout.strip.empty?
          return nil
        else
          target_process_pid_arr = cmd.stdout.strip.split("\n").map do |pid|
            (shell_out!("ps --no-header -o lstart #{pid}").stdout.strip
          end
          start_time_arr = Array.new()
          target_process_pid_arr.each do |t|
            if t != ""
              start_time_arr.push(Time.parse(t))
            end
          end
          return start_time_arr.sort.first.to_s
        end
      end
    end

    #
    # Function to check whether a process was started manually after restart of
    # the process failed during prev chef client run
    # Input: restart_failure_time - Last restart failure time
    #        process_identifier - string to identify the process
    # Returns: true (the process restarted since failing) or false (it did not)
    #
    def process_restarted_after_failure?(restart_failure_time,
                                         process_identifier)
      require 'time'
      begin
        start_time = process_start_time(process_identifier)
        if start_time.nil?
          return false
        elsif Time.parse(restart_failure_time).to_i < \
              Time.parse(start_time).to_i
          Chef::Log.info ("#{process_identifier} seem to be started at "
                          "#{start_time} after last restart failure at "
                          "#{restart_failure_time}") 
          return true
        else
          return false
        end
      end
    end
  end
end
