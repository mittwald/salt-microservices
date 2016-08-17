#!py

def run():
    import yaml
    import collections
    import urlparse

    consul_pattern     = salt['pillar.get']('consul:server_pattern', 'consul-server*')
    consul_targetmode  = salt['pillar.get']('consul:server_target_mode', 'glob')

    prom_config        = salt['pillar.get']('prometheus:configuration', {})
    prom_data_dir      = salt['pillar.get']('prometheus:data_dir', '/var/lib/prometheus')
    prom_internal_port = salt['pillar.get']('prometheus:internal_port', 9090)
    prom_alerts        = salt['pillar.get']('prometheus:alerts', {})

    alertmanager_proxy_url = salt['pillar.get']('alertmanager:proxy_url')
    alertmanager_path      = '/'

    if 'rule_files' not in prom_config:
        prom_config.update({'rule_files': ['alerts.rules']})

    if alertmanager_proxy_url is not None:
        parsed = urlparse.urlparse(alertmanager_proxy_url)
        alertmanager_path = parsed.path

    alert_config = '\n'.join(alert[1] for alert in sorted(prom_alerts.items()))

    return {
        '/etc/prometheus/prometheus.yml': {
            'file.managed': [
                {'makedirs': True},
                {'contents': yaml.dump(prom_config, default_flow_style=False)}
            ]
        },
        '/etc/prometheus/alerts.rules': {
            'file.managed': [
                {'makedirs': True},
                {'contents': alert_config}
            ]
        },
        prom_data_dir: {
            'file.directory': {
                {'makedirs': True}
            }
        },
        'prometheus': {
            'mwdocker.running': [
                {'image': 'prom/prometheus'},
                {'volumes': [
                    '/etc/prometheus:/prometheus-config',
                    '/var/lib/prometheus:/prometheus'
                ]},
                {'links': {'alertmanager': 'alertmanager'}},
                {'command': [
                    "-config.file=/prometheus-config/prometheus.yml",
                    "-alertmanager.url=http://alertmanager:9093%s" % alertmanager_path
                ]},
                {'tcp_ports': [
                    {'port': prom_internal_port, 'address': '0.0.0.0'}
                ]},
                {'dns': salt['grains.get']('fqdn_ip4')},
                {'warmup_wait': 10},
                {'labels': {
                    'service': 'prometheus',
                    'service_group': 'prometheus-main'
                }},
                {'require': [
                    {'service': 'docker'},
                    {'mwdocker': 'alertmanager'},
                    {'file': '/etc/prometheus/prometheus.yml'},
                    {'file': prom_data_dir},
                ]}
            ]
        }
    }
