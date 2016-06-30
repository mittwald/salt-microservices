{% set grafana_data_dir = salt['pillar.get']('grafana:data_dir', '/var/lib/grafana/data') %}
{% set grafana_plugin_dir = salt['pillar.get']('grafana:data_dir', '/var/lib/grafana/plugins') %}
{% set grafana_internal_port = salt['pillar.get']('grafana:internal_port', 3000) %}
{% set grafana_config = salt['pillar.get']('grafana:configuration', {}) %}
{% set grafana_ldap_config = salt['pillar.get']('grafana:ldap', {}) %}
{% set grafana_has_ldap_config = grafana_ldap_config | length > 0 %}

grafana-data-dir:
  file.directory:
    - name: {{ grafana_data_dir }}
    - makedirs: True

grafana-plugin-dir:
  file.directory:
    - name: {{ grafana_plugin_dir }}
    - makedirs: True

/etc/grafana/grafana.ini:
  file.managed:
    - makedirs: True
    - contents: |
        {% for section, values in grafana_config | dictsort -%}
        [{{ section }}]
        {% for key, value in values | dictsort -%}
        {{ key }} = {{ value }}
        {% endfor %}

        {% endfor %}

{% if grafana_has_ldap_config %}
/etc/grafana/ldap.toml:
  file.managed:
    - makedirs: True
    - contents: |
        {% for section, values in grafana_ldap_config | dictsort -%}
        {% if values is iterable and values is not mapping %}
        {% for item in values %}
        [[{{ section }}]]
        {% for key, value in item | dictsort -%}
        {{ key }} = {{ value | json }}
        {% endfor %}
        {% endfor %}
        {% else %}
        [{{ section }}]
        {% for key, value in values | dictsort -%}
        {{ key }} = {{ value | json }}
        {% endfor %}
        {% endif %}
        {% endfor %}
{% endif %}

grafana:
  mwdocker.running:
    - image: grafana/grafana
    - volumes:
      - {{ grafana_data_dir }}:/var/lib/grafana
      - {{ grafana_plugin_dir }}:/var/lib/grafana/plugins
      - /etc/grafana:/etc/grafana
    - tcp_ports:
      - port: {{ grafana_internal_port }}
        address: 0.0.0.0
    - links:
        prometheus: prometheus
    - warmup_wait: 10
    - dns: {{ salt['grains.get']('fqdn_ip4') }}
    - labels:
        service: prometheus
        service_group: prometheus-grafana
    - require:
      - file: grafana-data-dir
      - file: grafana-plugin-dir
      - file: /etc/grafana/grafana.ini
      {% if grafana_has_ldap_config %}
      - file: /etc/grafana/ldap.toml
      {% endif %}
      - mwdocker: prometheus
      - service: docker
