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

    config["include"] = [
        ".backup",
        ".nginx"
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
                    {"domain": "consul"}
                ]

                if 'http' in container_config and container_config['http']:
                    base_port = container_config['base_port']
                    host_port = base_port + container_number

                    container_state.append({"watch_in": [
                        {"file": "/etc/nginx/sites-available/service_%s.conf" % service_name},
                        {"file": "/etc/nginx/sites-enabled/service_%s.conf" % service_name}
                    ]})

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

                if 'check_url' in service_config:
                    check_url = service_config['check_url']
                else:
                    prot = 'http'

                    if 'ssl_certificate' in service_config:
                        prot = 'https'
                    if 'ssl_force' in service_config and not service_config['ssl_force']:
                        prot = 'http'

                    check_url = "%s://%s" % (prot, service_config["hostname"])

                # noinspection PyUnresolvedReferences
                checks.append({
                    "name": "HTTP connectivity",
                    "http": check_url,
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

        if has_http:
            config["/var/log/services/%s" % service_name] = {
                "file.directory": [
                    {"makedirs": True},
                    {"user": "www-data"},
                    {"group": "www-data"}
                ]
            }

            config["/etc/nginx/sites-available/service_%s.conf" % service_name] = {
                "file.managed": [
                    {"source": "salt://mwms/nginx/files/vhost.j2"},
                    {"template": "jinja"},
                    {"context": {
                        "service_name": service_name,
                        "service_config": service_config
                    }},
                    {"require": [{"file": "/var/log/services/%s" % service_name}]},
                    {"watch_in": [{"service": "nginx"}]}
                ]
            }

            config["/etc/nginx/sites-enabled/service_%s.conf" % service_name] = {
                "file.symlink": [
                    {"target": "/etc/nginx/sites-available/service_%s.conf" % service_name},
                    {"require": [
                        {"file": "/etc/nginx/sites-available/service_%s.conf" % service_name}
                    ]},
                    {"watch_in": [{"service": "nginx"}]}
                ]
            }

    return config
