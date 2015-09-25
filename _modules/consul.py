# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information

def reload():
	"""
	Reloads the consul configuration. This command requires the Consul
	executable to be installed on the node.
	"""
	__salt__['cmd.run']('consul reload')
