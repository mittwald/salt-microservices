#!py

import json

def run():
    consul_server_pattern = salt['pillar.get']('consul:server_pattern', 'consul-server*')
    consul_data_dir = salt['pillar.get']('consul:data_dir', '/var/lib/consul/data')

    consul_client_config = {
        "data_dir": consul_data_dir,
        "server": False,
        "node_name": salt['grains.get']('nodename'),
        "datacenter": salt['pillar.get']('consul:datacenter', 'dc1'),
        "client_addr": "127.0.0.1",
        "advertise_addr": salt['grains.get']('ip4_interfaces:eth0')[0],
        "start_join": [b[0] for a,b in __salt__['mine.get'](consul_server_pattern, 'network.ip_addrs').items()],
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
        "/etc/supervisor/conf.d/consul.conf": {
            "file.managed": [
                {"source": "salt://consul/files/supervisor-client.conf"},
                {"template": "jinja"},
                {"context": {"consul_data_dir": consul_data_dir}},
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
