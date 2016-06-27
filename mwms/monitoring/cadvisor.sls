{% set cadvisor_port = 8080 %}

/usr/local/sbin/cadvisor:
  file.managed:
    - source: salt://mwms/monitoring/files/cadvisor
    - mode: 755

/etc/supervisor/conf.d/cadvisor.conf:
  file.managed:
    - contents: |
        [program:cadvisor]
        command=/usr/local/sbin/cadvisor -port {{ cadvisor_port }}
    - require:
      - file: /usr/local/sbin/cadvisor
    - watch_in:
      - service: supervisor

/etc/consul/service-cadvisor.json:
  file.managed:
    - contents: |
        {
          "service": {
            "name": "cadvisor",
            "port": {{ cadvisor_port }}
          }
        }
    - require:
      - file: /etc/supervisor/conf.d/cadvisor.conf
    - watch_in:
      - cmd: consul-reload
