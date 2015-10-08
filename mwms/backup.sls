#!py

# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information

import json

def run():
    config = {}
    service_definitions = salt['pillar.get']('microservices', {})

    for service_name, service_config in service_definitions.items():
        for key, container_config in service_config['containers'].items():
            if not "backup" in container_config:
                continue

            backup_config = container_config["backup"]

            first_container_name = "%s-%s-0" % (service_name, key)
            image = backup_config["docker_image"]
            command = "bash -c '%s'" % backup_config["command"] if "command" in backup_config else ""

            backup_dir = "/var/backups/service/%s/%s" % (service_name, key)

            config[backup_dir] = {
                "file.directory": [
                    {"makedirs": True}
                ]
            }

            backup_command = "docker run --rm --link %s:source -v %s/$(date +%%Y%%m%%d):/target --volumes-from %s %s %s" % (first_container_name, backup_dir, first_container_name, image, command)

            config[backup_command] = {
                "cron.present": [
                    {"identifier": "backup-%s-%s" % (service_name, key)},
                    {"user": "root"},
                    {"hour": 3},
                    {"minute": 0},
                    {"require": [
                        {"file": backup_dir}
                    ]}
                ]
            }

    return config
