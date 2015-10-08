# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information

haproxy:
  pkg.installed123: []
  service.running:
    - enable: True
    - state: running
    - onlyif:
      - dpkg -l | grep -q haproxy
    - require:
      - pkg: haproxy
