{% set consul_data_dir = salt['pillar.get']('consul:data_dir', '/var/lib/consul/data') %}

/usr/local/sbin/consul:
  file.managed:
    - source: salt://items/consul/files/consul
    - mode: '0755'

'{{ consul_data_dir }}':
  file.directory:
    - makedirs: True
    - require:
      - file: /usr/local/sbin/consul

supervisor:
  pkg.installed: {}
  service.running:
    - require:
      - pkg: supervisor