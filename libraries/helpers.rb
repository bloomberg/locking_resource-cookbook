module LockingResource
  module Helper
    class LockingResourceException < Exception
    end

    include Chef::Mixin::ShellOut

    # XXX test and define me
    def parse_zk_hosts(servers)
      servers.join(',')
    end

    #
    # Set some state to flag that a locking resource needs to be re-run
    # Inputs:
    #   node - A node object which we can update
    #   path - A lock path string to use for saving the rerun state
    # Side-effect: writes a Time object and failure count to the node object if
    #              previously unset otherwise increments failure count
    # Returns: A hash with the following keys
    #       "time" : Time object stored in the node object
    #       "fails" : number of times this lock has failed
    #  
    def need_rerun(node, path)
      failed_locks = Proc.new { node[:locking_resource][:failed_locks] }
      failed_locks_set = Proc.new do |key, val|
        node.normal[:locking_resource][:failed_locks][key] = val
      end
      if failed_locks.call.fetch(path, false)
        failed_locks_set.call(path, {
          "time" => failed_locks.call[path]["time"],
          "fails" => failed_locks.call[path]["fails"] + 1 })
      else
        failed_locks_set.call(path,
                              { "time" => Time.now, "fails" => 1 })
      end
      puts "XXX #{failed_locks.call[path]}"
      return failed_locks.call[path]
    end

    #
    # Returns the rerun time saved in the node object
    # Inputs:
    #   node - A node object which we can update
    #   path - A lock path string to use for saving the rerun state
    # Returns: returns the Time object from the node object or nil if not set
    #
    def rerun_time?(node, path)
      puts "XXX rerun_time #{path}"
      node[:locking_resource][:failed_locks].fetch(
        path, {"time" => nil})["time"]
    end

    #
    # Clears out the Time object saved in the node object
    # Inputs:
    #   node - A node object which we can update
    #   path - A lock path string to use for saving the rerun state
    # Returns: returns the Time object from the node object or nil if not set
    #
    def clear_rerun(node, path)
      node.normal[:locking_resource][:failed_locks].delete(path)
    end

    #
    # Run an arbitrary block of code against a Zookeeper connection
    # Inputs:
    #     quorum - 'localhost:2181' by default, comma separated
    #                        e.g. ("zk_host1:port,sk_host2:port")
    #     &block - the code to run
    # Return value : return of the block
    #                or nil if connection can not be estabilished
    #
    def run_zk_block(quorum_hosts, &block)
      val = nil
      if !quorum_hosts
         raise ArgumentError, "Need non nil quorum_hosts"
      end
      require 'zookeeper'
      begin
        zk = Zookeeper.new(quorum_hosts)
        unless zk.connected?
          fail ::LockingResource::Helper::LockingResourceException,
            "LockingResource: unable to connect to ZooKeeper quorum " \
            "#{quorum_hosts}"
        end
        val = block.call(zk)
      rescue ::LockingResource::Helper::LockingResourceException => e
        Chef::Log.warn e.message
        raise
      rescue StandardError => e
        Chef::Log.warn e.message
        raise
      # make sure we always try to clean-up
      ensure
        begin
          zk.close unless (zk.nil? || zk.closed?)
        rescue StandardError => e
          Chef::Log.warn e.message
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
    def create_node(quorum_hosts, path, data)
      # walk tree creating any necessary znodes:
      unless get_node_data(quorum_hosts, path)
        Chef::Log.debug "Did not find node: #{path}"

        # affect a mkdir -p equivalent
        pieces = path.split(File::SEPARATOR)
        pieces = pieces.map.with_index do |p, i|
          # create an ascending list of paths e.g.
          # ['/foo', '/foo/bar', '/foo/bar/baz', etc.]
          pieces.slice(0, i+1).join(File::SEPARATOR)
        end.select{ |p| p.length > 0 && !get_node_data(quorum_hosts, p) }

        # create parent nodes
        run_zk_block(quorum_hosts) do |zk|
          pieces.slice(0, pieces.length-1).each do |p|
            ret = zk.create(path: p, data: '')
            Chef::Log.debug "Tried to create node: #{p}; #{ret}"
            fail ::LockingResource::Helper::LockingResourceException,
              "Failed to create: #{p}" unless ret[:rc] == 0
          end
        end
      end # unless get_node_Data(quorum_hosts, parent_path)

      run_zk_block(quorum_hosts) do |zk|
        ret = zk.create(path: path, data: data)
        Chef::Log.debug "Tried to create node: #{path}; #{ret}"
        ret[:rc] == 0
      end ? true : false
    end

    #
    # This function is to check whether the lock to restart a particular
    # service is held by a node (check the znode's data matches the string
    # provided). The input parameters are the path to the znode used to
    # restart a hadoop service, a string containing the host port values
    # of the ZooKeeper nodes 'host1:port, host2:port' and
    # the fqdn of the host
    # Return value : true or false
    #
    def lock_matches?(quorum_hosts, path, data)
      run_zk_block(quorum_hosts) do |zk|
        ret = zk.get(path: path)
        val = ret[:data]
        true if val == data
      end ? true : false
    end

    #
    # Function to release the lock held by the node to restart a particular
    # hadoop service. The input parameters are the name of the path to znode
    # which was used to lock for restarting service, string containing the
    # zookeeper host and port ('host1:port,host2:port') and the fqdn of the
    # node trying to release the lock.
    # Return value : true or false based on whether the lock release was
    #                successful or not
    # Raises: If the node does not provide correct data
    #         (and does not remove lock)
    #
    def release_lock(quorum_hosts, path, data)
      run_zk_block(quorum_hosts) do |zk|
        if lock_matches?(quorum_hosts, path, data)
          ret = zk.delete(path: path)
        else
          fail ::LockingResource::Helper::LockingResourceException,
            'release_lock: node does not contain expected data ' \
            'not releasing the lock'
        end
        true if ret[:rc] == 0
      end ? true : false # ensure we catch returning nil and make it false
    end

    #
    # Function to get the node data which is written to a particular path
    # Input parameters:
    #     quorum - 'localhost:2181' by default, comma separated
    #                        e.g. ('zk_host1:port,sk_host2:port')
    #     path - the znode name to query
    # Return value    : The data of the node or nil
    #
    def get_node_data(quorum_hosts, path)
      run_zk_block(quorum_hosts) do |zk|
        ret = zk.get(path: path)
        ret[:data] if ret[:rc] == 0
      end
    end

    #
    # Function to get the lock creation time
    # Input parameters:
    #     quorum - 'localhost:2181' by default, comma separated
    #                        e.g. ('zk_host1:port,sk_host2:port')
    #     path - the znode name to query
    # Return value    : A Ruby time object of the node's creation or nil
    #
    def get_node_ctime(quorum_hosts, path)
      require 'time'
      run_zk_block(quorum_hosts) do |zk|
        ret = zk.stat(path: path)
        Time.strptime(ret[:stat].ctime.to_s, '%Q') if ret[:rc] == 0
      end
    end

    #
    # Function to identify start time of a process
    # Input: command_string - 'pgrep ' compatible process search string
    #        full_cmd - boolean whether to use use 'pgrep -f' for command string
    #        user - use 'pgrep -u <user>' for search string
    #
    # Returns: A Ruby Time object representing the eldest process's start time
    #          or nil
    # Note:
    # * If the process can not be found, nil is returned
    #
    # ensure VALID_PROCESS_PATTERN_OPTS matches the arguments
    # available process_start_time()
    VALID_PROCESS_PATTERN_OPTS = {full_cmd: false,
                                  command_string: nil,
                                  user: nil}
    def process_start_time(full_cmd: false, command_string: nil, user: nil)
      require 'time'

      raise 'Need a command_string or user to search for:' if \
        (command_string.nil? and user.nil?)
      # pgrep options mapped to command arguments
      cmd_opts = [(user and %Q{-u "#{user}"}),
                  (full_cmd and '-f'),
                  (command_string and %Q{"#{command_string}"})].\
        select{|m| m}.join(' ')
      cmd = shell_out!("pgrep -o #{cmd_opts}", returns: [0, 1])
      # raise for any error
      Chef::Log.debug "process_start_time() pgrep -o #{cmd_opts}:"\
                      "#{cmd.stderr}, #{cmd.stdout}"
      fail cmd.stderr unless cmd.stderr.empty?

      if cmd.stdout.strip.empty?
        nil
      else
        pid = cmd.stdout.strip.split("\n").first
        cmd = shell_out!("ps --no-header -o lstart #{pid}",
                          returns: [0, 1])
        # raise for any error
        fail cmd.stderr unless cmd.stderr.empty?
        Chef::Log.debug "process_start_time() ps:#{cmd.stdout}, #{cmd.stderr}"
        t = cmd.stdout.strip
        Time.parse(t) if t != ''
      end
    end
  end
end
