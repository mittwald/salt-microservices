# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information

{% set consul_data_dir = salt['pillar.get']('consul:data_dir', '/var/lib/consul/data') %}
{% set consul_config_dir = salt['pillar.get']('consul:config_dir', '/etc/consul') %}

include:
  - mwms.supervisor

/usr/local/sbin/consul:
  file.managed:
    - source: salt://mwms/consul/files/consul
    - mode: '0755'

'{{ consul_data_dir }}':
  file.directory:
    - makedirs: True
    - require:
      - file: /usr/local/sbin/consul

'{{ consul_config_dir }}':
  file.directory:
    - makedirs: True
    - require:
      - file: /usr/local/sbin/consul
