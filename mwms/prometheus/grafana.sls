{# set alertmanager_config = salt['pillar.get']('alertmanager:configuration', {}) #}
{% set grafana_data_dir = salt['pillar.get']('grafana:data_dir', '/var/lib/grafana/data') %}
{% set grafana_plugin_dir = salt['pillar.get']('grafana:data_dir', '/var/lib/grafana/plugins') %}

grafana-data-dir:
  file.directory:
    - name: {{ grafana_data_dir }}
    - makedirs: True

grafana-plugin-dir:
  file.directory:
    - name: {{ grafana_plugin_dir }}
    - makedirs: True

grafana:
  mwdocker.running:
    - image: grafana/grafana
    - volumes:
      - {{ grafana_data_dir }}:/var/lib/grafana
      - {{ grafana_plugin_dir }}:/var/lib/grafana/plugins
    - tcp_ports:
      - port: 3000
        address: 0.0.0.0
    - links:
        prometheus: prometheus
    - warmup_wait: 10
    - labels:
        service: prometheus
        service_group: prometheus-grafana
    - require:
      - file: grafana-data-dir
      - file: grafana-plugin-dir
      - mwdocker: prometheus
      - service: docker
