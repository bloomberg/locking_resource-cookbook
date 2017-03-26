###########################################
#
#  Locking resource specific configs
#
#############################################
# The path in ZK where the restart locks (znodes)  need to be created
# The path should exist in ZooKeeper e.g. '/lock'
default['locking_resource']['restart_lock']['root'] = '/lock'
# Where we store failed lock attempts to run in a future Chef run
default['locking_resource']['failed_locks'] = {}
# Sleep time in seconds between tries to acquire the lock for restart
default['locking_resource']['restart_lock_acquire']['sleep_time'] = 0.25
# Timeout in seconds before failing to acquire lock
default['locking_resource']['restart_lock_acquire']['timeout'] = 30
# Flag to control whether automatic restarts due to config changes need to be
# skipped for e.g. if ZK quorum is down or if the recipes need to be run in a
# non ZK env
default['locking_resource']['skip_restart_coordination'] = false
# The default zookeeper quorum
default['locking_resource']['zookeeper_servers'] = ['localhost:2181']
