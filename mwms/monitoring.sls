{% set cadvisor_port = 8080 %}

cadvisor:
  mwdocker.running:
    - image: google/cadvisor
    - volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
    - tcp_ports:
      - port: 8080
        host_port: {{ cadvisor_port }}
        address: 0.0.0.0

/etc/consul/service-cadvisor.json:
  file.managed:
    - contents: |
        {
          "service": {
            "name": "cadvisor",
            "port": {{ cadvisor_port }}
          }
        }
    - watch_in:
      - cmd: consul-reload
