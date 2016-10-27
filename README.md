## Description
The locking resource cookbook provides resources to lock various other Chef resources. This can be used to  prevent a distributed environment from having multiple machines simultaneously executing a particular resouce. 

Use cases envisioned:
* Prevent stampeding herds knocking over a particularly fragile end-point by serializing access
* Prevent all instances of a service going down en mass during configuration updates
* Communicate state if a particular service is not coming back up (preventing a toxic-configuration from causing cascading failures) and still verifiying if a process is restarted outside of Chef using process start time.

## Requirements
The Zookeeper gem and a Zookeeper cluster is required. While envisioned to use a generic synchronous state enginer, today Zookeeper is used for all lock coordination.

## Attributes
* `node[:locking_resource][:restart_lock][:root]` - Zookeeper namespace underwhich all locks are created
* `node[:locking_resource][:restart_lock_acquire][:sleep_time]` - Sleep time in (fractions-of) seconds between tries to acquire a lock for restart
* `node[:locking_resource][:restart_lock_acquire][:timeout]` - Timeout in seconds before failing to acquire lock
* `node[:locking_resource][:skip_restart_coordination]` - Flag to skip attempting lock coordination (will just assume lock was acquired and not block)
* `node[:locking_resource][:zookeeper_servers]` - The default zookeeper quorum

## Resources
* `locking_resource` - The HWRP for achieving locking

### Actions
* `:serialize` - Will run the requested action every Chef run as long as a lock can be acquired 
* `:serialize_process` - Is like `:serialize` except that should it leave a stale lock, it also verifies if the specified process has restarted since the lock was acquired and if so, cleans-up the lock not restarting again

#### `:serialize`
Will run the requested action every Chef run as long as a lock can be acquired 

##### Relevant Attributes
* `:resource` - String name of resource to control (uses the same `'resource[name]'` syntax as `:notifies`/`:subscribes`)
* `:perform` - Action to perform on `:resource` when called (locked resources are often set to `:nothing` to avoid running outside of lock)
* `:timeout` - Optional timeout override for resources which might hold a lock particularly long
* `:lock_data` - Optional data to put in lock; (envisioned to provide ability to lock on a topology grouping e.g. a rack)

#### `:serialize_process`
Will run the requested action every Chef run as long as a lock can be acquired; provides extra features for a process affecting resource. Will verify that if the machine is found to be holding a stale lock and the process as restarted since the lock was taken out, the lock will be released with no action. This provides an ability for a service to fail restarting (e.g. due to an exogenous resource failure; like a disk), to take out a lock to prevent other like processes going down electively and to be cleared by an administrator (e.g. disk replaced) and for Chef to clear the condition automatically.

* `:process_pattern` - Takes a block of options to define the process to keep an eye on:
 * `full_cmd` - Boolean as to if `pgrep(1)` should use `-f` for a full command string search
 * `command_string` - The process string to search for (e.g. `java`)
 * `user` - The numeric UID or ASCII username string of the user running the process
 * Only `user` or `command_string` need be supplied (both may be)

Contributing
============
Contributions are welecomed! This cookbook tries to have rigerous testing to verify that locks are held and released as expected. The current process for kicking these off on a machine with ChefDK is:
````
$ bundler --path=vendor/cache
$ berks vendor
$ bundler exec rspec
$ kitchen converge '.*'
````
