try:
    import docker
    import docker.utils
    import docker.errors
except ImportError:
    def __virtual__():
        return False, ["The docker-py package is not installed"]

import json
import logging
import time


log = logging.getLogger(__name__)


def container_ip(name):
    client = docker.Client(base_url='unix://var/run/docker.sock')
    info = client.inspect_container(name)
    return info['NetworkSettings']['IPAddress']


def container_published_port(name, container_port):
    client = docker.Client(base_url='unix://var/run/docker.sock')
    info = client.inspect_container(name)
    return info['NetworkSettings']['Ports'][container_port]['HostPort']


def start_container(name, warmup_wait=60):
    log.info("Starting container %s" % name)
    client = docker.Client(base_url='unix://var/run/docker.sock')
    client.start(name)

    # We need to sleep to prevent race conditions on application startup.
    # For example, Flow applications that do a doctrine:migrate on startup.
    log.info("Waiting %d seconds for container to start" % warmup_wait)
    time.sleep(warmup_wait)

    container_status = client.inspect_container(name)
    if not container_status["State"]["Running"] or container_status["State"]["Restarting"]:
        raise Exception('Container %s is not running after %d seconds. Status is: %s' % (
            name, warmup_wait, container_status["State"]))


def image_id(image):
    if ':' not in image:
        image += ":latest"

    client = docker.Client(base_url='unix://var/run/docker.sock')
    images = client.images()

    for existing_image in images:
        if image in existing_image['RepoTags']:
            return existing_image['Id']
    return None


def delete_container(name):
    log.info("Deleting container %s" % name)
    client = docker.Client(base_url='unix://var/run/docker.sock')

    try:
        client.inspect_container(name)
    except docker.errors.NotFound:
        log.info("Container %s was not present in the first place." % name)
        return

    client.stop(name)
    client.remove_container(name)


def create_container(name, image, command=None, environment=None, volumes=(), udp_ports=None, tcp_ports=None,
                     restart=True, dns=None, domain=None, volumes_from=None, links=None, user=None, test=False):

    client = docker.Client(base_url='unix://var/run/docker.sock')

    pull_image(image, force=False, test=test)

    hostconfig_ports, ports = _create_port_definitions(udp_ports, tcp_ports)
    hostconfig_binds, binds = _create_volume_definitions(volumes)

    print(hostconfig_binds)

    restart_policy = None
    if restart:
        restart_policy = {
            "MaximumRetryCount": 0,
            "Name": "always"
        }

    host_config = docker.utils.create_host_config(
        binds=hostconfig_binds,
        port_bindings=hostconfig_ports,
        restart_policy=restart_policy,
        dns=dns,
        dns_search=[domain],
        volumes_from=volumes_from,
        links=links
    )

    if test:
        log.info("Would create container %s" % name)
        return None

    log.info("Creating container %s" % name)
    container = client.create_container(
        name=name,
        image=image,
        command=command,
        ports=ports,
        host_config=host_config,
        volumes=binds,
        environment=environment,
        user=user
    )
    return container['Id']


def pull_image(image, force=False, test=False):
    client = docker.Client(base_url='unix://var/run/docker.sock')

    if ':' not in image:
        image += ":latest"

    images = client.images()

    present = False
    for existing_image in images:
        if image in existing_image['RepoTags']:
            present = True

    repository, tag = image.split(':')

    if not present or force:
        if test:
            log.info("Would pull image %s:%s" % (repository, tag))
        else:
            # noinspection PyUnresolvedReferences
            log.info("Pulling image %s:%s" % (repository, tag))
            pull_stream = client.pull(repository, tag, stream=True)
            for line in pull_stream:
                j = json.loads(line)
                if 'error' in j:
                    raise Exception("Could not pull image %s:%s: %s" % (repository, tag, j['errorDetail']))


def _create_port_definitions(udp_ports, tcp_ports):
    ports = []
    port_bindings = {}

    def walk_ports(port_definitions, protocol):
        for binding in port_definitions:
            host_port = binding['host_port'] if 'host_port' in binding else binding['port']
            ports.append((binding['port'], protocol))
            port_bindings["%d/%s" % (binding['port'], protocol)] = (binding['address'], host_port)

    walk_ports(tcp_ports, 'tcp')
    walk_ports(udp_ports, 'udp')

    return port_bindings, ports


def _create_volume_definitions(volumes):
    binds = {}
    container_volumes = []

    for bind in volumes:
        r = bind.split(':')
        mode = r[2] if len(r) > 2 else "rw"

        container_volumes.append(r[1])
        binds[r[0]] = {
            "bind": r[1],
            "mode": mode
        }

    return binds, container_volumes
