# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information

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
