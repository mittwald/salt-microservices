#!py

# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information

import json

def run():
    config = {}
    service_definitions = salt['pillar.get']('microservices')

    config["include"] = [
        ".backup",
        "mwms.haproxy"
    ]

    dns_ip = salt['grains.get']('ip4_interfaces:eth0')[0]
    for service_name, service_config in service_definitions.items():
        for key, container_config in service_config['containers'].items():
            container_name = "%s-%s" % (service_name, key)

            if 'volumes' in container_config:
                for dir, mount, mode in container_config['volumes']:
                    volume_host_path = '/var/lib/services/' + service_name + '/' + dir
                    config[volume_host_path] = {
                        "file.directory": [
                            {"mode": "0777"},
                            {"makedirs": True}
                        ]
                    }

            for container_number in range(container_config['instances']):
                container_instance_name = "%s-%d" % (container_name, container_number)

                requirements = [
                    {"service": "docker"}
                ]

                container_state = [
                    {"image": container_config['docker_image']},
                    {"stateful": container_config["stateful"]},
                    {"dns": [dns_ip]},
                    {"domain": "consul"},
                    {"watch_in": [{"file": "/etc/haproxy/haproxy.cfg"}]}
                ]

                if 'http' in container_config and container_config['http']:
                    base_port = container_config['base_port']
                    host_port = base_port + container_number

                    container_port = 80
                    if 'http_internal_port' in container_config:
                        container_port = container_config['http_internal_port']

                    container_state.append({"tcp_ports": [{"address": "127.0.0.1", "port": container_port, "host_port": host_port}]})
                elif 'ports' in container_config:
                    container_state.append({"tcp_ports": container_config['ports']})

                links = {}
                if 'links' in container_config:
                    for linked_container, alias in sorted(container_config['links'].items()):
                        linked_container_name = "%s-%s-0" % (service_name, linked_container)
                        links[linked_container_name] = alias
                        requirements.append({"mwdocker": linked_container_name})

                if len(links) > 0:
                    container_state.append({"links": links})

                passthrough_args = ("environment", "restart", "user", "command")
                for p in passthrough_args:
                    if p in container_config:
                        container_state.append({p: container_config[p]})

                if "volumes" in container_config:
                    volumes = []
                    for dir, mount, mode in container_config["volumes"]:
                        source_dir = "/var/lib/services/%s/%s" % (service_name, dir)
                        volumes.append(
                            "%s:%s:%s" % (
                            source_dir, mount, mode))
                        requirements.append({"file": source_dir})
                    container_state.append({"volumes": volumes})

                if len(requirements) > 0:
                    container_state.append({"require": requirements})

                config[container_instance_name] = {
                    "mwdocker.running": container_state
                }

        has_http = False
        has_port = None

        if "hostname" in service_config:
            config[service_config["hostname"]] = {
                "host.present": [
                    {"ip": "127.0.0.1"}
                ]
            }

        for key, c in service_config["containers"].items():
            if "http" in c and c["http"]:
                has_http = True
            if "ports" in c and has_port is None:
                has_port = c["ports"][0]

        if has_http or has_port is not None:
            consul_service = {"name": service_name}
            checks = service_config["checks"] if "checks" in service_config else []

            if has_http:
                consul_service["port"] = 80

                # noinspection PyUnresolvedReferences
                checks.append({
                    "name": "HTTP connectivity",
                    "http": "http://%s" % (service_config["hostname"]),
                    "interval": "1m"
                })
            else:
                consul_service["port"] = has_port

            if len(checks) > 0:
                consul_service["checks"] = checks

            config["/etc/consul/service-%s.json" % service_name] = {
                "file.managed": [
                    {"contents": json.dumps({"service": consul_service}, indent=4)},
                    {"watch_in": [{"cmd": "consul-reload"}]}
                ]
            }

    config["/etc/haproxy/haproxy.cfg"] = {
        "file.managed": [
            {"source": "salt://mwms/files/haproxy.conf.j2"}
        ]
    }

    return config
