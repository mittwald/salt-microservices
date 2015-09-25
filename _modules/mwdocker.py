# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information


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
    """
    Determines the internal IP address of a Docker container.

    :param name: The container name
    :return: The container's internal IP address
    """
    client = docker.Client(base_url='unix://var/run/docker.sock')
    info = client.inspect_container(name)
    return info['NetworkSettings']['IPAddress']


def container_published_port(name, container_port):
    """
    Gets the port number of a publicly exposed container port.

    :param name: The container name
    :param int: The internal container port
    :return: The host port that the container port is mapped on
    """
    client = docker.Client(base_url='unix://var/run/docker.sock')
    info = client.inspect_container(name)
    return info['NetworkSettings']['Ports'][container_port]['HostPort']


def start_container(name, warmup_wait=60):
    """
    Starts a Docker container. This function will wait for a defined amount of
    time to check if the container actually stays up after being started. If the
    container status is not "up" after the `warmup_wait` has expired, this
    function will raise an exception.

    :param name: The container name
    :param int: How long this function should wait to check the container status
    """
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
    """
    Gets the image ID for a specified image name.

    :param image: The image name
    :return: The image ID
    """
    if ':' not in image:
        image += ":latest"

    client = docker.Client(base_url='unix://var/run/docker.sock')
    images = client.images()

    for existing_image in images:
        if image in existing_image['RepoTags']:
            return existing_image['Id']
    return None


def delete_container(name):
    """
    Stops and deletes a container.

    :param name: Name of the container to delete
    """
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
    """
    Creates a new container.

    :param name: The container name
    :param image: The image from which to create the container
    :param command: The command to use for the container
    :param environment: A dictionary of environment variables to pass into the
        container
    :param volumes: A list of volumes. Each volume definition is a string of the
        format "<host-directory>:<container-directory>:<rw|ro>"
    :param udp_ports: UDP ports to expose. This is a list of dictionaries that
        must provide a "port" and an "address" key.
    :param tcp_ports: TCP ports to expose. This is a list of dictionaries that
        must provide a "port" and an "address" key.
    :param restart: `True` to restart the container when it stops
    :param dns: A list of DNS server addresses to use
    :param domain: The DNS search domain
    :param volumes_from: A list of container names from which to use the volumes
    :param links: A dictionary of containers to link (using the container name
        as index and the alias as value)
    :param user: The user under which to start the container
    :param test: Set to `True` to not actually do anything
    """

    client = docker.Client(base_url='unix://var/run/docker.sock')

    pull_image(image, force=False, test=test)

    hostconfig_ports, ports = _create_port_definitions(udp_ports, tcp_ports)
    hostconfig_binds, binds = _create_volume_definitions(volumes)

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
    """
    Pulls the current version of an image.

    :param image: The image name. If no tag is specified, the `latest` tag is assumed
    :param force: Set to `True` to pull even when a local image of the same name exists
    :param test: Set to `True` to not actually do anything
    """
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
