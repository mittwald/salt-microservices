/etc/resolv.conf:
  file.managed:
    - source: salt://consul/files/agent-resolv.conf
