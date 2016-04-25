#!py

# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information

import json


def run():
    consul_server_pattern = salt['pillar.get']('consul:server_pattern', 'consul-server*')
    consul_server_targetmode = salt['pillar.get']('consul:server_target_mode', 'glob')
    consul_data_dir = salt['pillar.get']('consul:data_dir', '/var/lib/consul/data')
    consul_config_dir = salt['pillar.get']('consul:config_dir', '/etc/consul')

    peers = salt['mine.get'](consul_server_pattern, 'network.ip_addrs', expr_form=consul_server_targetmode).items()

    consul_client_config = {
        "data_dir": consul_data_dir,
        "server": False,
        "node_name": salt['grains.get']('nodename'),
        "datacenter": salt['pillar.get']('consul:datacenter', 'dc1'),
        "client_addr": "127.0.0.1",
        "advertise_addr": salt['grains.get']('ip4_interfaces:eth0')[0],
        "start_join": [addresses[0] for name, addresses in peers],
        "recursors": salt['pillar.get']('consul:nameservers', ["8.8.8.8"]),
        "dns_config": {
            "allow_stale": True,
            "max_stale": "5m"
        },
        "ports": {
            "dns": int(__salt__['pillar.get']('consul:ports:udp:dns', 53))
        }
    }

    return {
        "include": [
            "mwms.consul.common.install",
            "mwms.supervisor"
        ],
        "/etc/consul/agent.json": {
            "file.managed": [
                {"contents": json.dumps(consul_client_config, indent=4)},
                {"makedirs": True}
            ]
        },
        "/etc/consul/server.json": {
            "file.absent": []
        },
        "/etc/supervisor/conf.d/consul.conf": {
            "file.managed": [
                {"source": "salt://mwms/consul/files/supervisor-agent.conf"},
                {"template": "jinja"},
                {"context": {
                    "consul_data_dir": consul_data_dir,
                    "consul_config_dir": consul_config_dir
                }},
                {"watch_in": [
                    {"service": "supervisor"}
                ]},
                {"require": [
                    {"pkg": "supervisor"},
                    {"file": "/usr/local/sbin/consul"},
                    {"file": consul_data_dir}
                ]}
            ]
        },
        "consul-reload": {
            "module.wait": [
                {"name": "consul.reload"},
                {"watch": [{"file": "/etc/consul/agent.json"}]}
            ]
        }
    }
