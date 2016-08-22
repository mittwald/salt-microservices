# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information


import requests
import json
import salt.states.file


def node(name, address, datacenter=None, service=None):
    """
    This state registers a new external node using the Consul REST API.

    [1] https://www.consul.io/docs/agent/http/catalog.html#catalog_register

    :param name: The node name
    :param address: A resolvable address (IP address or hostname) under which the node can be reached
    :param datacenter: The data center name
    :param service: A Consul service definition (see [1] for more information)
    """
    r = requests.get('http://localhost:8500/v1/catalog/node/%s' % name)
    repr = {
        "Node": name,
        "Address": address
    }

    if datacenter is not None:
        repr["Datacenter"] = datacenter

    if service is not None:
        repr["Service"] = service
        repr["Service"]["Address"] = ""

        if "Tags" not in repr["Service"]:
            repr["Service"]["Tags"] = None

    changed = False
    if r.status_code == 200:
        existing = r.json()

        if existing is not None:
            if existing["Node"]["Address"] != repr["Address"]:
                changed = True
            if datacenter is not None and existing["Datacenter"] != repr["Datacenter"]:
                changed = True
            if service is not None and existing["Services"][repr["Service"]["ID"]] != repr["Service"]:
                changed = True
        else:
            changed = True

    if r.status_code == 404 or changed:
        ret = {
            'name': name,
            'result': True,
            'changes': {"service": {"old": r.json(), "new": repr}},
            'comment': 'Registered node'
        }

        if not __opts__['test']:
            r = requests.put('http://localhost:8500/v1/catalog/register', data=json.dumps(repr))
            if r.status_code != 200:
                print(r.text)
                raise Exception('Unexected status: %d' % r.status_code)
    else:
        ret = {
            'name': name,
            'result': True,
            'changes': {},
            'comment': 'Node is up to spec'
        }

    return ret


def service(name, config_dir='/etc/consul', port=80, check_type=None, check_url=None, check_script=None,
            check_interval="1m", check_name='default health check'):
    """
    This state registers a new service in Consul. This is done by placing a
    static configuration file into Consul's `config-dir`.

    :param name: The service name
    :param config_dir: The consul configuration directory
    :param port:  The port that the service is available on
    :param check_type: The type to use for the health check (either "http", "script" or `None`)
    :param check_url: The URL to use for the HTTP health check
    :param check_script: The script to use for the script health check
    :param check_interval: The check interval in a time interval format parseable by Go
    :param check_name: The health check's name
    :return:
    """
    service_definition = {
        'service': {
            'name': name,
            'port': port
        }
    }

    if check_type == "http":
        if check_url is None:
            raise Exception('When check_type is "http", a check_url must be specified!')
        if check_script is not None:
            raise Exception('When check_type is "http", no check_script must be specified!')

        service_definition['checks'] = [
            {
                'interval': check_interval,
                'http': check_url,
                'name': 'HTTP connectivity'
            }
        ]
    elif check_type == 'script':
        if check_url is not None:
            raise Exception('When check_type is "script", no check_url must be specified!')
        if check_script is not None:
            raise Exception('When check_type is "script", a check_script must be specified!')

        service_definition['checks'] = [
            {
                'interval': check_interval,
                'script': check_script,
                'name': check_name
            }
        ]
    elif check_type is None:
        pass
    else:
        raise Exception('bad check_type: "%s". Allowed are "http" and "script".' % check_type)

    service_json = json.dumps(service_definition)
    service_file = '%s/service-%s.json' % (config_dir, name)

    return salt.states.file.managed(name=service_file, contents=service_json)
