# Copyright (c) 2015 Martin Helmich <m.helmich@mittwald.de>
#                    Mittwald CM Service GmbH & Co. KG
#
# Docker-based microservice deployment with service discovery
# This code is MIT-licensed. See the LICENSE.txt for more information

import logging
import docker
import docker.errors

logger = logging.getLogger(__name__)


def redeploy(service_name, tag_override='latest'):
    """
    Re-deploys a service. This module tries to pull the Docker image from which
    an application container is created. If a newer version of the image could
    be pulled, this module will sequentially delete the containers and re-create
    them.

    :param service_name: The name of the service to re-deploy
    :param tag_override: The default tag to use (if no image tag was specified)
        in the service definition pillar.
    """

    try:
        service_definition = __salt__['pillar.get']('microservices:%s' % service_name)
    except KeyError:
        return {
            "result": True,
            "changes": {},
            "comment": "service is not registered on this host"
        }

    client = docker.Client(base_url='unix://var/run/docker.sock')
    result = {
        "container_images": {},
        "container_ids": {}
    }

    for key, container_config in service_definition['containers'].items():
        image_name = container_config['docker_image']

        if ':' not in image_name:
            image_name += ":%s" % tag_override

        __salt__['mwdocker.pull_image'](image_name, force=True)
        current_image_id = __salt__['mwdocker.image_id'](image_name)

        for container_number in range(container_config['instances']):
            container_name = "%s-%s-%d" % (service_name, key, container_number)

            try:
                existing_container_info = client.inspect_container(container_name)
                used_image_id = existing_container_info['Image']
                result["container_ids"][container_name] = {"old": existing_container_info["Id"]}
            except docker.errors.NotFound:
                existing_container_info = None
                used_image_id = None
                result["container_ids"][container_name] = {"old": None}

            result["container_images"][container_name] = {
                "old": used_image_id,
                "new": current_image_id
            }

            if used_image_id == current_image_id:
                result["container_ids"][container_name]["new"] = result["container_ids"][container_name]["old"]
                continue

            if existing_container_info is not None:
                if 'stateful' in container_config and container_config['stateful']:
                    logger.warn("Container %s needs to be updates (current image version is %s), but is stateful. Please upgrade yourself." % (container_name, current_image_id))
                    result["container_ids"][container_name]["new"] = None
                    continue
                logger.info("Deleting container %s" % container_name)
                __salt__['mwdocker.delete_container'](container_name)

            links = {}
            if 'links' in container_config:
                for linked_container, alias in sorted(container_config['links'].items()):
                    linked_container_name = "%s-%s-0" % (service_name, linked_container)
                    links[linked_container_name] = alias

            volumes_from = None
            if 'volumes_from' in container_config:
                volumes_from = []
                for volume_container in container_config['volumes_from']:
                    volume_container_name = "%s-%s-0" % (service_name, volume_container)
                    volumes_from.append(volume_container_name)

            volumes = []
            if "volumes" in container_config:
                volumes = []
                for dir, mount, mode in container_config["volumes"]:
                    source_dir = "/var/lib/services/%s/%s" % (service_name, dir)
                    volumes.append("%s:%s:%s" % (source_dir, mount, mode))

            ports = []
            if 'http' in container_config and container_config['http']:
                base_port = container_config['base_port']
                host_port = base_port + container_number

                container_http_port = 80
                if 'http_internal_port' in container_config:
                    container_http_port = container_config['http_internal_port']

                ports.append({"address": "127.0.0.1", "port": container_http_port, "host_port": host_port})
            elif 'ports' in container_config:
                ports += container_config['ports']

            container_id = __salt__['mwdocker.create_container'](
                name=container_name,
                image=image_name,
                environment=container_config["environment"] if "environment" in container_config else None,
                links=links,
                volumes=volumes,
                volumes_from=volumes_from,
                udp_ports=[],
                tcp_ports=ports,
                restart=container_config["restart"] if "restart" in container_config else True,
                user=container_config["user"] if "user" in container_config else None,
                command=container_config["command"] if "command" in container_config else None,
                dns=[__salt__['grains.get']('ip4_interfaces:eth0')[0]],
                domain="consul"
            )
            result["container_ids"][container_name]["new"] = container_id

            __salt__['mwdocker.start_container'](container_name)
            logger.info("Created container %s with id %s" % (container_name, container_id))


    return result
