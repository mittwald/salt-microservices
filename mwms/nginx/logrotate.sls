# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information

/etc/logrotate.d/services:
  file.managed:
    - contents: |
        /var/log/services/*/access.log {
          daily
          missingok
          rotate 30
          compress
          delaycompress
          notifempty
          create 0640 www-data adm
          postrotate
            invoke-rc.d nginx rotate >/dev/null 2>&1
          endscript
        }
