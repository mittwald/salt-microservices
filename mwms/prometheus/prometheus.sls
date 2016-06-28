{% set consul_pattern = salt['pillar.get']('consul:server_pattern', 'consul-server*') -%}
{% set consul_targetmode = salt['pillar.get']('consul:server_target_mode', 'glob') -%}

{% set prom_config = salt['pillar.get']('prometheus:configuration', {}) %}
{% set prom_data_dir = salt['pillar.get']('prometheus:data_dir', '/var/lib/prometheus') %}
{% set prom_internal_port = salt['pillar.get']('prometheus:internal_port', 9090) %}
{% set prom_alerts = salt['pillar.get']('prometheus:alerts', {}) %}

{% if not 'rule_files' in prom_config %}
{% do prom_config.update({'rule_files': ['alerts.rules']}) %}
{% endif %}

/etc/prometheus/prometheus.yml:
  file.managed:
    - makedirs: True
    - contents: {{ prom_config | yaml }}

/etc/prometheus/alerts.rules:
  file.managed:
    - makedirs: True
    - contents: |
        {% for name, alert in prom_alerts | dictsort %}
        {{ alert | indent(8) }}
        {% endfor %}

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
    - dns: {{ salt['grains.get']('fqdn_ip4') }}
    - warmup_wait: 10
    - labels:
        service: prometheus
        service_group: prometheus-main
    - require:
      - service: docker
      - mwdocker: alertmanager
      - file: /etc/prometheus/prometheus.yml
      - file: {{ prom_data_dir }}
