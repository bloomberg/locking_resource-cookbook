name             'locking_resource_test'
maintainer       'Bloomberg LP'
maintainer_email 'compute@bloomberg.net'
license          'Apache 2.0'
description      'Installs and configures locking_resource cookbook for testing'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.1.0'

depends 'zookeeper', '=6.0.0'
depends 'locking_resource'
