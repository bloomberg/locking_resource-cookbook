#
# Cookbook Name:: locking_resource
# Library:: locking_resource
#
# Copyright (C) 2016 Bloomberg Finance L.P.
#
require 'poise'
class Chef
  class Resource::LockingResource < Resource
    include Poise
    provides(:locking_resource)

    actions(:serialize)
    default_action(:serialize)

    attribute(:name, kind_of: String)
    attribute(:resource, kind_of: String, required: true)
    attribute(:perform, kind_of: Symbol, required: true)
    attribute(:timeout, kind_of: Integer, default: 30)

    # XXX should validate node[:locking_resource][:zookeeper_servers] parses
  end

  class Provider::LockingResource < Provider
    include Poise
    include ::Locking_Resource::Helper
    provides(:locking_resource)

    def action_serialize
      converge_by("serializing #{new_resource.name} via lock") do
        zk_hosts = parse_zk_hosts(node[:locking_resource][:zookeeper_servers])
        r = run_context.resource_collection.resources(new_resource.resource)
        # to avoid namespace collisions replace spaces in resource name with
        # a colon -- zookeeper's quite permissive on paths:
        # https://zookeeper.apache.org/doc/trunk/zookeeperProgrammers.html#ch_zkDataModel
        lock_path = ::File.join(node[:locking_resource][:restart_lock][:root],
                              new_resource.name.gsub(' ', ':'))
        start_time = Time.now

        Chef::Log.info "Acquiring lock #{lock_path}"
        # acquire lock
        got_lock = lock_matches?(zk_hosts, lock_path, node[:fqdn]) and \
          Chef::Log.info "Found stale lock"
        # intentionally do not use a timeout to avoid leaving a wonky zookeeper
        # object or connection if we interrupt it -- thus we trust the
        # zookeeper object to not wantonly hang
        while !got_lock && start_time + timeout <= Time.now
          got_lock = create_node(zk_hosts, lock_path, node[:fqdn]) and \
            Chef::Log.info "Acquired new lock"
        end

        # affect the resource, if we got the lock -- or error
        if got_lock
          notifying_block do
            r.run_action new_resource.perform
            r.resolve_notification_references
            new_resource.updated_by_last_action(r.updated)
            release_lock(zk_hosts, lock_path, node[:fqdn])
          end
        else
          raise 'Failed to acquire lock for ' +
                "LockingResource[#{new_resource.name}], path #{lock_path}"
        end
      end
    end
  end
end

