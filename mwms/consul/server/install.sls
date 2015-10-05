#!py

# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information

import json


def run():
    consul_server_pattern = salt['pillar.get']('consul:server_pattern', 'consul-server*')
    consul_data_dir = salt['pillar.get']('consul:data_dir', '/var/lib/consul/data')
    consul_ui_dir = salt['pillar.get']('consul:ui_dir', '/var/lib/consul/ui')
    consul_config_dir = salt['pillar.get']('consul:config_dir', '/etc/consul')

    peers = salt['mine.get'](consul_server_pattern, 'network.ip_addrs').items()

    consul_client_config = {
        "data_dir": consul_data_dir,
        "server": True,
        "node_name": salt['grains.get']('nodename'),
        "datacenter": salt['pillar.get']('consul:datacenter', 'dc1'),
        "client_addr": "0.0.0.0",
        "advertise_addr": salt['grains.get']('ip4_interfaces:eth0')[0],
        "bootstrap_expect": len(peers),
        "start_join": [addresses[0] for name, addresses in peers],
        "recursors": salt['pillar.get']('consul:nameservers', ["8.8.8.8"]),
        "ports": {
            "dns": int(__salt__['pillar.get']('consul:ports:udp:dns', 53))
        }
    }

    return {
        "include": [
            "mwms.consul.common.install",
            "mwms.supervisor"
        ],
        "/etc/consul/server.json": {
            "file.managed": [
                {"contents": json.dumps(consul_client_config, indent=4)},
                {"makedirs": True}
            ]
        },
        consul_ui_dir: {
            "archive.extracted": [
                {"source": "salt://consul/files/0.5.2_web_ui.zip"},
                {"archive_format": "zip"},
                {"unless": "test -d %s" % consul_ui_dir }
            ]
        },
        "/etc/supervisor/conf.d/consul.conf": {
            "file.managed": [
                {"source": "salt://mwms/consul/files/supervisor.conf"},
                {"template": "jinja"},
                {"context": {
                    "consul_data_dir": consul_data_dir,
                    "consul_ui_dir": consul_ui_dir,
                    "consul_config_dir": consul_config_dir
                }},
                {"watch_in": [
                    {"service": "supervisor"}
                ]},
                {"require": [
                    {"pkg": "supervisor"},
                    {"file": "/usr/local/sbin/consul"},
                    {"file": consul_data_dir},
                    {"archive": consul_ui_dir}
                ]}
            ]
        },
        "consul-reload": {
            "module.wait": [
                {"name": "consul.reload"},
                {"watch": [{"file": "/etc/consul/server.json"}]}
            ]
        }
    }
