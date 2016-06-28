{% set alertmanager_config = salt['pillar.get']('alertmanager:configuration', {}) %}
{% set alertmanager_data_dir = salt['pillar.get']('alertmanager:data_dir', '/var/lib/alertmanager') %}

/etc/prometheus/alertmanager.yml:
  file.managed:
    - makedirs: True
    - contents: {{ alertmanager_config | yaml }}

alertmanager:
  mwdocker.running:
    - image: prom/alertmanager
    - volumes:
      - /etc/prometheus:/prometheus-config
      - {{ alertmanager_data_dir }}:/alertmanager
    - command:
      - "-config.file=/prometheus-config/alertmanager.yml"
    - tcp_ports:
      - port: 9093
        address: 0.0.0.0
    - warmup_wait: 10
    - dns: {{ salt['grains.get']('fqdn_ip4') }}
    - labels:
        service: prometheus
        service_group: prometheus-alertmanager
    - require:
      - service: docker
