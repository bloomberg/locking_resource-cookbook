module Locking_Resource
  module Helper
    class LockingResourceException < Exception
    end

    include Chef::Mixin::ShellOut
   
    #
    # Run an arbitrary block of code against a Zookeeper connection
    # Inputs:
    #     quorum - 'localhost:2181' by default, comma separated
    #                        e.g. ("zk_host1:port,sk_host2:port")
    #     &block - the code to run
    # Return value : return of the block
    #                or exception if connection can not be estabilished
    #
    def run_zk_block(quorum_hosts='localhost:2181', &block)
      require 'zookeeper'
      val = nil
      begin
        zk = Zookeeper.new(quorum_hosts)
        if !zk.connected?
          raise LockingResourceException, \
                  "Locking_Resource: unable to connect to ZooKeeper quorum " \
                  "#{quorum_hosts}"
        end
        val = block.call(zk)
      rescue LockingResourceException => e
        raise
      rescue StandardError => e
        Log.warn e.message
      # make sure we always try to clean-up
      ensure
        begin
          if !zk.nil?
            zk.close unless zk.closed? 
          end
        rescue LockingResourceException => e
          raise
        rescue StandardError => e
          Log.warn e.message
        end
        val
      end
    end

    #
    # Restarting of processes need to be controlled in a way that all
    # the nodes are not down at the sametime, the consequence of which will
    # impact users. In order to achieve this, nodes need to acquire a lock
    # before restarting the process of interest. This function is to acquire
    # the lock which is stored as a znode in zookeeper. The znode name should
    # be the name of the service to be restarted (e.g "hadoop-hdfs-datanode")
    # and is located by default at "/".
    # Inputs:
    #     quorum - 'localhost:2181' by default, comma separated
    #                        e.g. ("zk_host1:port,sk_host2:port")
    #     path - the znode name to create
    #     data - the data to put in the znode
    # Return value : true or false
    #
    def create_node(quorum_hosts='localhost:2181', path, data)
      run_zk_block(quorum_hosts) do |zk|
        ret = zk.create(:path => path, :data => data)
        if ret[:rc] == 0
          lock_acquired = true
        end
      end ? true : false # ensure we catch returning nil and make it false
    end

    #
    # This function is to check whether the lock to restart a particular
    # service is held by a node (check the znode's data matches the string
    # provided). The input parameters are the path to the znode used to
    # restart a hadoop service, a string containing the host port values
    # of the ZooKeeper nodes "host1:port, host2:port" and
    # the fqdn of the host
    # Return value : true or false
    #
    def lock_matches?(quorum_hosts='localhost:2181', path, data)
      run_zk_block(quorum_hosts) do |zk|
        ret = zk.get(:path => path)
        val = ret[:data]
        if val == data
          found_lock = true
        end
      end ? true : false # ensure we catch returning nil and make it false
    end

    #
    # Function to release the lock held by the node to restart a particular
    # hadoop service. The input parameters are the name of the path to znode
    # which was used to lock for restarting service, string containing the
    # zookeeper host and port ("host1:port,host2:port") and the fqdn of the
    # node trying to release the lock.
    # Return value : true or false based on whether the lock release was
    #                successful or not
    # Raises: If the node does not provide correct data
    #         (and does not remove lock)
    #
    def release_lock(quorum_hosts='localhost:2181', path, data)
      run_zk_block(quorum_hosts) do |zk|
        if lock_matches?(quorum_hosts, path, data)
          ret = zk.delete(:path => path)
        else
          raise LockingResourceException, \
            'release_lock: node does not contain expected data '
            'not releasing the lock'
        end
        if ret[:rc] == 0
          lock_released = true
        end
      end ? true : false # ensure we catch returning nil and make it false
    end

    #
    # Function to get the node data which is written to a particular path
    # Input parameters: 
    #     quorum - 'localhost:2181' by default, comma separated
    #                        e.g. ("zk_host1:port,sk_host2:port")
    #     path - the znode name to query
    # Return value    : The data of the node or nil
    #
    def get_node_data(quorum_hosts='localhost:2181', path)
      run_zk_block(quorum_hosts) do |zk|
        ret = zk.get(:path => path)
        if ret[:rc] == 0
          val = ret[:data]
        end
      end
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
        elsif root == '/'
          return "/#{lock_name}"
        else
          return "#{root}/#{lock_name}"
        end
      end
    end

    #
    # Function to identify start time of a process
    # Input: process_identifier - 'pgrep -f' compatible process search string
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
        Log.debug "XXXlib pgrep #{cmd.stderr}, XXX #{cmd.stdout}"
        raise cmd.stderr if !cmd.stderr.empty?

        if cmd.stdout.strip.empty?
          return nil
        else
          start_time_arr = cmd.stdout.strip.split("\n").map do |pid|
            cmd = shell_out!("ps --no-header -o lstart #{pid}",
                             {:returns => [0, 1]})
            # raise for any error
            raise cmd.stderr if !cmd.stderr.empty?
            Log.debug "XXXlib ps #{cmd.stderr}, XXX #{cmd.stdout}"
            t = cmd.stdout.strip
            if t != ''
              Time.parse(t)
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
        Log.debug "XXX praf #{restart_failure_time}, #{process_identifier}"
        start_time = process_start_time(process_identifier)
        Log.debug "XXX praf #{start_time}"
        if start_time.nil?
          return false
        elsif Time.parse(restart_failure_time).to_i < \
              Time.parse(start_time).to_i
          Chef::Log.info ("#{process_identifier} seem to be started at " \
                          "#{start_time} after last restart failure at " \
                          "#{restart_failure_time}") 
          return true
        else
          return false
        end
      end
    end
  end
end
