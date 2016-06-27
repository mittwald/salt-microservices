{% set prom_config = salt['pillar.get']('prometheus:configuration', {}) %}
{% set prom_data_dir = salt['pillar.get']('prometheus:data_dir', '/var/lib/prometheus') %}
{% set prom_internal_port = salt['pillar.get']('prometheus:internal_port', 9090) %}

/etc/prometheus/prometheus.yml:
  file.managed:
    - makedirs: True
    - contents: {{ prom_config | yaml }}

{{ prom_data_dir }}:
  file.directory:
    - makedirs: True

prometheus:
  mwdocker.running:
    - image: prom/prometheus
    - volumes:
      - /etc/prometheus:/prometheus-config
      - /var/lib/prometheus:/prometheus
    - links:
        alertmanager: alertmanager
    - command:
      - "-config.file=/prometheus-config/prometheus.yml"
      - "-alertmanager.url=http://alertmanager:9093/"
    - tcp_ports:
      - port: {{ prom_internal_port }}
        address: 0.0.0.0
    - warmup_wait: 10
    - labels:
        service: prometheus
        service_group: prometheus-main
    - require:
      - service: docker
      - mwdocker: alertmanager
      - file: /etc/prometheus/prometheus.yml
      - file: {{ prom_data_dir }}
