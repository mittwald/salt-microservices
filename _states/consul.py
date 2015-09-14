
import requests
import json

def node(name, address, datacenter=None, service=None):
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
