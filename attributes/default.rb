###########################################
#
#  Locking resource specific configs
#
#############################################
# Number of tries to acquire the lock required to restart the process
default[:locking_resource][:restart_lock_acquire][:max_tries] = 5
# The path in ZK where the restart locks (znodes)  need to be created
# The path should exist in ZooKeeper e.g. '/lock'
default[:locking_resource][:restart_lock][:root] = '/lock'
# Sleep time in seconds between tries to acquire the lock for restart
default[:locking_resource][:restart_lock_acquire][:sleep_time] = 2
# Timeout in seconds before failing to acquire lock
default[:locking_resource][:restart_lock_acquire][:timeout] = 30
# Flag to set whether the HDFS datanode restart process was successful or not
default[:locking_resource][:hadoop_hdfs_datanode][:restart_failed] = false
# Attribute to save the time when HDFS datanode restart process failed
default[:locking_resource][:hadoop_hdfs_datanode][:restart_failed_time] = ''
# Flag to control whether automatic restarts due to config changes need to be
# skipped for e.g. if ZK quorum is down or if the recipes need to be run in a
# non ZK env
default[:locking_resource][:skip_restart_coordination] = false
# The default zookeeper quorum
default[:locking_resource][:zookeeper_servers] = ['localhost:2181']
