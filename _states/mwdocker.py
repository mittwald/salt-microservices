# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information


import docker.errors
import docker
import logging


log = logging.getLogger(__name__)

if not '__opts__' in globals():
    log.fatal("Whoops! __opts__ not set!?")
    __opts__ = {}
if not '__salt__' in globals():
    log.fatal("Whoops! __salt__ not set!?")
    __salt__ = {}


def running(name, image, volumes=(), restart=True, tcp_ports=(), udp_ports=(), environment=None, command=None, dns=None,
            domain=None, volumes_from=None, links=None, user=None, warmup_wait=60, stateful=False):
    """
    Asserts that a container matching the provided specification is up and
    running.

    :param name: The container name
    :param image: The image from which to create the container
    :param volumes: A list of volumes. Each volume definition is a string of the format "<host-directory>:<container-directory>:<rw|ro>"
    :param restart: `True` to restart the container when it stops
    :param tcp_ports: TCP ports to expose. This is a list of dictionaries that must provide a "port" and an "address" key
    :param udp_ports: UDP ports to expose. This is a list of dictionaries that must provide a "port" and an "address" key
    :param environment: A dictionary of environment variables to pass into the container
    :param command: The command to use for the container
    :param dns: A list of DNS server addresses to use
    :param domain: The DNS search domain
    :param volumes_from: A list of container names from which to use the volumes
    :param links: A dictionary of containers to link (using the container name as index and the alias as value)
    :param user: The user under which to start the container
    :param warmup_wait: The amount of time to wait for the container to start
    :param stateful: Set to `True` to prevent this container from automatic deletion
    """
    ret = {
        'name': name,
        'result': True,
        'changes': {},
        'comment': ''
    }
    client = docker.Client(base_url='unix://var/run/docker.sock')

    if ':' not in image:
        image += ":latest"

    # noinspection PyCallingNonCallable
    __salt__['mwdocker.pull_image'](image, force=False, test=__opts__['test'])

    try:
        existing = client.inspect_container(name)
    except docker.errors.NotFound:
        existing = None

    if existing is not None:
        matches_spec = __does_existing_container_matches_spec(client, ret, existing, name, image, tcp_ports=tcp_ports,
                                                              volumes=volumes, udp_ports=udp_ports,
                                                              environment=environment, command=command, dns=dns,
                                                              volumes_from=volumes_from, links=links, domain=domain)

        if not matches_spec and stateful:
            ret["result"] = False
            ret["comment"] = 'Existing container does not match specification, and I\'m to scared to delete it.'
            return ret
        elif not matches_spec:
            ret['comment'] += "Deleting old version of container %s\n" % name
            if not __opts__['test']:
                # noinspection PyCallingNonCallable
                __salt__['mwdocker.delete_container'](name)
        else:
            ret['comment'] += 'Container exists and is up to spec.\n'
            return ret

    if not __opts__['test']:
        # noinspection PyCallingNonCallable
        container_id = __salt__['mwdocker.create_container'](
            name=name,
            image=image,
            command=command,
            environment=environment,
            links=links,
            volumes=volumes,
            volumes_from=volumes_from,
            udp_ports=udp_ports,
            tcp_ports=tcp_ports,
            restart=restart,
            dns=dns,
            domain=domain,
            user=user,
            test=__opts__['test']
        )

        ret['changes']['container'] = {'new': container_id}
        ret['changes']['running'] = {'old': False, 'new': True}

        __salt__['mwdocker.start_container'](name, warmup_wait=warmup_wait)
    else:
        ret['changes']['container'] = {'new': '<NEW-CONTAINER-ID>'}
        ret['changes']['running'] = {'old': False, 'new': True}

    return ret


def __does_existing_container_matches_spec(client, ret, existing, name, image, volumes=(), restart=True, tcp_ports=(),
                                           udp_ports=(), environment=None, command=None, dns=None, volumes_from=None,
                                           links=None, domain=None):
    up_to_spec = True
    image_id = __salt__['mwdocker.image_id'](image)

    if existing['Image'] != image_id:
        ret['changes']['image'] = {'old': existing['Image'], 'new': image_id}
        up_to_spec = False

    for volume in volumes:
        try:
            source_dir, mount, mode = volume.split(':')
        except ValueError:
            source_dir, mount = volume.split(':')

        if mount not in existing['Volumes']:
            ret['changes']['volumes/%s' % mount] = {'new': volume, 'old': None}
            up_to_spec = False
        elif existing['Volumes'][mount] != source_dir:
            ret['changes']['volumes/%s' % mount] = {'new': volume,
                                                    'old': "%s:%s:%s" % (existing['Volumes'][mount], mount, '??')}
            up_to_spec = False

    if restart and existing['HostConfig']['RestartPolicy']['Name'] != 'always':
        ret['changes']['restart'] = {'old': False, 'new': True}
        up_to_spec = False
    if not restart and existing['HostConfig']['RestartPolicy']['Name'] == 'always':
        ret['changes']['restart'] = {'old': True, 'new': False}
        up_to_spec = False

    for port in tcp_ports:
        port_name = "%d/tcp" % port['port']
        host_port = port['host_port'] if 'host_port' in port else port['port']
        should = [{"HostIp": port["address"], "HostPort": str(host_port)}]

        if existing['NetworkSettings']['Ports'] is None or not port_name in existing['NetworkSettings']['Ports']:
            ret['changes']['ports/tcp/%d' % port['port']] = {'old': False, 'new': port}
            up_to_spec = False
        elif existing['NetworkSettings']['Ports'][port_name] != should:
            ret['changes']['ports/tcp/%d' % port['port']] = {'old': existing['NetworkSettings']['Ports'][port_name],
                                                             'new': should}
            up_to_spec = False

    for port in udp_ports:
        port_name = "%d/udp" % port['port']
        host_port = port['host_port'] if 'host_port' in port else port['port']
        should = {"HostIp": port["address"], "HostPort": str(host_port)}

        if existing['NetworkSettings']['Ports'] is None or not port_name in existing['NetworkSettings']['Ports']:
            ret['changes']['ports/udp/%d' % port['port']] = {'old': False, 'new': port}
            up_to_spec = False
        elif existing['NetworkSettings']['Ports'][port_name] != should:
            ret['changes']['ports/udp/%d' % port['port']] = {'old': existing['NetworkSettings']['Ports'][port_name],
                                                             'new': should}
            up_to_spec = False

    if environment is not None:
        for key, value in environment.items():
            if ("%s=%s" % (key, value)) not in existing['Config']['Env']:
                ret['changes']['env/%s' % key] = {'old': None, 'new': "%s=%s" % (key, value)}
                up_to_spec = False

    if command is not None:
        joined_command = command
        if type(command) is list:
            joined_command = " ".join(command)
        if " ".join(existing['Config']['Cmd']) != joined_command:
            ret['changes']['command'] = {'old': " ".join(existing['Config']['Cmd']), 'new': joined_command}
            up_to_spec = False

    if dns is not None and existing['HostConfig']['Dns'] != dns:
        ret['changes']['dns'] = {'old': existing['HostConfig']['Dns'], 'new': dns}
        up_to_spec = False

    if volumes_from is not None and existing['HostConfig']['VolumesFrom'] != volumes_from:
        ret['changes']['volumes_from'] = {'old': existing['HostConfig']['VolumesFrom'], 'new': volumes_from}
        up_to_spec = False

    if links is not None:
        docker_format = ["/%s:%s/%s" % (a, existing["Name"], b) for a, b in links.items()]
        if existing['HostConfig']['Links'] != docker_format:
            ret['changes']['links'] = {'old': existing['HostConfig']['Links'], 'new': docker_format}
            up_to_spec = False

    if domain is not None:
        if existing['HostConfig']['DnsSearch'] != [domain]:
            ret['changes']['domain'] = {'old': existing['HostConfig']['DnsSearch'], 'new': [domain]}
            up_to_spec = False

    return up_to_spec
