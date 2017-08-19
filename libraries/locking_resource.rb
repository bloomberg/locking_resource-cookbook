#
# Cookbook Name:: locking_resource
# Library:: locking_resource
#
# Copyright (C) 2017 Bloomberg Finance L.P.
#
require 'poise'
require 'set'
class Chef
  class Resource::LockingResource < Resource
    include Poise
    provides(:locking_resource)

    actions(:serialize)
    actions(:serialize_process)
    default_action(:serialize)

    attribute(:name, kind_of: String)
    attribute(:lock_name, kind_of: String, default: nil)
    attribute(:resource, kind_of: String, required: true)
    attribute(:perform, kind_of: Symbol, required: true)
    attribute(:timeout, kind_of: Integer, default: \
      lazy { node['locking_resource']['restart_lock_acquire']['timeout'] })
    attribute(:zookeeper_hosts, kind_of: Array, default: \
      lazy { node['locking_resource']['zookeeper_servers'] })
    attribute(:process_pattern, option_collector: true)
    attribute(:lock_data, kind_of: String, default: lazy { node['fqdn'] })

    # XXX should validate node['locking_resource']['zookeeper_servers'] parses
  end

  class Provider::LockingResource < Provider
    include Poise
    require_relative 'helpers.rb'
    include ::LockingResource::Helper
    provides(:locking_resource)

    #
    # Loops trying to acquire lock and returns true if lock acquired,
    # false otherwise
    # Inputs:
    #   zk_hosts   - a string of <host>:<port>,<host>:<port>,... for ZK hosts
    #   lock_path  - the path for the lock
    #   lock_data  - the data to record in the lock, if we acquire the lock
    #   timeout    - the overall time to try acquiring the lock
    #   retry_time - the time to re-try acquiring the lock (should be less
    #                than and a multiple of the total timeout)
    def acquire_lock(zk_hosts, lock_path, lock_data, timeout, retry_time)
      Chef::Log.info "Acquiring lock #{lock_path}"
      # acquire lock
      # rubocop:disable Style/AndOr
      got_lock = lock_matches?(zk_hosts, lock_path, lock_data) \
        and Chef::Log.info 'Found stale lock'
      # rubocop:enable Style/AndOr

      # intentionally do not use a timeout to avoid leaving a wonky
      # zookeeper object or connection if we interrupt it -- thus we trust
      # the zookeeper object to not wantonly hang
      start_time = Time.now
      while !got_lock && (start_time + timeout) >= Time.now
        # rubocop:disable Style/AndOr
        got_lock = create_node(zk_hosts, lock_path, lock_data) \
          and Chef::Log.info 'Acquired new lock'
        # rubocop:enable Style/AndOr
        sleep(retry_time)
        Chef::Log.warn "Sleeping for lock #{lock_path}"
      end
      # see if we ever got a lock -- if not record it for later
      Chef::Log.warn "Did not get lock #{lock_path}" unless got_lock
      got_lock
    end

    #
    # Used to action a resource with locking semantics
    def action_serialize
      converge_by("serializing #{new_resource.name}") do
        r = run_context.resource_collection.resources(new_resource.resource)
        unless r
          raise "Unable to find resource #{new_resource.resource} in " \
                'resources'
        end

        # to avoid namespace collisions replace spaces in resource name with
        # a colon -- zookeeper's quite permissive on paths:
        # https://zookeeper.apache.org/doc/trunk/zookeeperProgrammers.html#ch_zkDataModel
        lock_name = new_resource.lock_name || new_resource.name.tr_s(' ', ':')
        lock_path = ::File.join(
          node['locking_resource']['restart_lock']['root'],
          lock_name
        )

        zk_hosts = parse_zk_hosts(new_resource.zookeeper_hosts)
        if node['locking_resource']['skip_restart_coordination']
          got_lock = false
          Chef::Log.warn 'Restart coordination disabled -- skipping lock ' \
                         "acquisition on #{lock_path}"
        else
          loop_time = \
            node['locking_resource']['restart_lock_acquire']['sleep_time']
          got_lock = acquire_lock(zk_hosts, lock_path, new_resource.lock_data,
                                  new_resource.timeout, loop_time)
        end

        # affect the resource, if we got the lock -- or error
        if got_lock || node['locking_resource']['skip_restart_coordination']
          notifying_block do
            r.run_action new_resource.perform
            r.resolve_notification_references
            new_resource.updated_by_last_action(r.updated)
            begin
              release_lock(zk_hosts, lock_path, new_resource.lock_data)
            rescue ::LockingResource::Helper::LockingResourceException => e
              Chef::Log.warn e.message
            end
          end
        else
          need_rerun(node, lock_path)
          raise 'Failed to acquire lock for ' \
                "LockingResource[#{new_resource.name}], path #{lock_path}"
        end
      end
    end

    # Only restart the service if we are holding the lock
    # and the service has not restarted since we started trying to get the lock
    def action_serialize_process
      vppo = ::LockingResource::Helper::VALID_PROCESS_PATTERN_OPTS
      raise 'Need a process pattern attribute' if \
        new_resource.process_pattern.empty?
      if Set.new(new_resource.process_pattern.keys) < \
         Set.new(vppo.keys)
        raise "Only expect options: #{vppo.keys} but got " \
              "#{new_resource.process_pattern.keys}"
      end
      converge_by("serializing #{new_resource.name} on process") do
        l_time = false
        lock_and_rerun = false

        r = run_context.resource_collection.resources(new_resource.resource)
        zk_hosts = parse_zk_hosts(new_resource.zookeeper_hosts)

        # convert keys from strings to symbols for process_start_time()
        start_time_arg = \
          new_resource.process_pattern.each_with_object({}) do |(k, v), memo|
            memo[k.to_sym] = v
          end

        p_start = process_start_time(start_time_arg) || false

        # questionable if we want to include cookbook_name and recipe_name in
        # the lock as we may have multiple resources with the same name
        lock_name = new_resource.lock_name || new_resource.name.tr_s(' ', ':')
        lock_path = ::File.join(
          node['locking_resource']['restart_lock']['root'],
          lock_name
        )

        r_time = rerun_time?(node, lock_path)
        begin
          got_lock = lock_matches?(zk_hosts, lock_path, new_resource.lock_data)
          l_time = get_node_ctime(zk_hosts, lock_path) if got_lock
        rescue ::LockingResource::Helper::LockingResourceException => e
          Chef::Log.warn e.message
        end
        Chef::Log.warn 'Found stale lock' if got_lock

        # if process is started see if we need to restart it again
        if p_start
          node_rerun_needed = p_start <= (r_time || Time.new(0))
          lock_rerun_needed = p_start <= (l_time || Time.new(0))
          lock_and_rerun = node_rerun_needed || lock_rerun_needed
        end

        # if we are not running the process -- run! Otherwise if we have a
        # past, failed restart attempt, re-run
        if !p_start || lock_and_rerun
          Chef::Log.info 'Restarting process: lock time: ' \
                         "#{l_time}; rerun flag time: #{r_time}; " \
                         "process restarted since lock: #{p_start}"
          notifying_block do
            r.run_action new_resource.perform
            r.resolve_notification_references
            new_resource.updated_by_last_action(r.updated)
          end
        else
          Chef::Log.info "Not restarting process: lock time: #{l_time}; " \
                         "rerun flag time: #{r_time}; " \
                         "process restarted since lock: #{p_start}"
        end

        # we should not get here if restarting the resource failed --
        # so clean everything up
        clear_rerun(node, lock_path)
        begin
          # release_lock will not matter if we are not holding the lock
          release_lock(zk_hosts, lock_path, new_resource.lock_data)
        rescue ::LockingResource::Helper::LockingResourceException => e
          Chef::Log.warn e.message
        end
      end
    end
  end
end
