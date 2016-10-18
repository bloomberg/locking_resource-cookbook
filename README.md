Description
===========
The locking resource cookbook provides a definition to lock various Chef resources preventing a distributed environment from having multiple machines simultaneously executing a particular resouce. This is often useful for service restarts to prevent services going down en mass during configuration updates.

Requirements
============
The Zookeeper gem and a Zookeeper cluster is required as Zookeeper is used for all lock coordination

Attributes
==========


Usage
=====

Contributing
============
$ bundler
$ berks vendor
$ bundler exec rspec
