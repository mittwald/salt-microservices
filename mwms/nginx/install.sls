nginx:
  pkg.installed:
    - require:
      - pkg: haproxy
  service.running:
    - enable: True
    - require:
      - pkg: nginx

haproxy:
  pkg.removed: []

/etc/nginx/sites-enabled/default:
  file.absent:
    - require:
      - pkg: nginx
    - watch_in:
      - service: nginx

/etc/nginx/nginx.conf:
  file.managed:
    - source: salt://mwms/nginx/files/nginx.conf.j2
    - template: jinja
    - require:
      - pkg: nginx
    - watch_in:
      - service: nginx
