/var/log/infra/prometheus:
  file.directory:
    - makedirs: True

/var/log/infra/grafana:
  file.directory:
    - makedirs: True

/etc/nginx/sites-available/infra_prometheus.conf:
  file.managed:
    - source: salt://mwms/prometheus/files/prometheus-vhost.conf
    - template: jinja
    - context:
        server_name: {{ salt['pillar.get']('prometheus:proxy:server_name', 'prometheus.example.org') }}
        prometheus_internal_port: {{ salt['pillar.get']('prometheus:internal_port', 9090) }}
        alertmanager_internal_port: {{ salt['pillar.get']('alertmanager:internal_port', 9093) }}
        ssl_certificate: {{ salt['pillar.get']('prometheus:proxy:ssl_certificate') }}
        ssl_key: {{ salt['pillar.get']('prometheus:proxy:ssl_key') }}
    - require:
      - file: /var/log/infra/prometheus
    - watch_in:
      - service: nginx

/etc/nginx/sites-enabled/infra_prometheus.conf:
  file.symlink:
    - target: /etc/nginx/sites-available/infra_prometheus.conf
    - require:
      - file: /etc/nginx/sites-available/infra_prometheus.conf
    - watch_in:
      - service: nginx

/etc/nginx/sites-available/infra_grafana.conf:
  file.managed:
    - source: salt://mwms/prometheus/files/grafana-vhost.conf
    - template: jinja
    - context:
        server_name: {{ salt['pillar.get']('grafana:proxy:server_name', 'grafana.example.org') }}
        internal_port: {{ salt['pillar.get']('grafana:internal_port', 3000) }}
        ssl_certificate: {{ salt['pillar.get']('grafana:proxy:ssl_certificate') }}
        ssl_key: {{ salt['pillar.get']('grafana:proxy:ssl_key') }}
    - require:
      - file: /var/log/infra/grafana
    - watch_in:
      - service: nginx

/etc/nginx/sites-enabled/infra_grafana.conf:
  file.symlink:
    - target: /etc/nginx/sites-available/infra_grafana.conf
    - require:
      - file: /etc/nginx/sites-available/infra_grafana.conf
    - watch_in:
      - service: nginx
