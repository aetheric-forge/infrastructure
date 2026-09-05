"""Extract only the two known migration fields from kubectl's JSON output."""
import json
import sys


def adoption_items(documents):
    items = []
    for doc in documents:
        if doc.get('kind') == 'List':
            items.extend(adoption_items(doc['items']))
            continue
        meta = doc.get('metadata', {})
        identity = (doc.get('apiVersion'), doc.get('kind'), meta.get('namespace'), meta.get('name'))
        item = {'apiVersion': doc.get('apiVersion'), 'kind': doc.get('kind'),
                'metadata': {k: meta[k] for k in ('name', 'namespace') if k in meta}}
        if identity == ('v1', 'Service', 'forge-mongo', 'forge-mongo-lb'):
            key = 'kubernetes.civo.com/firewall-id'
            item['metadata']['annotations'] = {key: meta['annotations'][key]}
        elif identity == ('postgresql.cnpg.io/v1', 'Cluster', 'forge-db', 'forge-db'):
            # This CRD list is atomic: Kubernetes ownership is for the whole list.
            item['spec'] = {'managed': {'services': {'additional': doc['spec']['managed']['services']['additional']}}}
        else:
            continue
        items.append(item)
    return items


def main():
    text = sys.stdin.read().strip()
    decoder = json.JSONDecoder()
    documents = []
    while text:
        doc, end = decoder.raw_decode(text)
        documents.append(doc)
        text = text[end:].lstrip()
    items = adoption_items(documents)
    if len(items) != 2:
        raise SystemExit('Expected exactly the MongoDB Service and PostgreSQL Cluster for adoption')
    if '--release' in sys.argv:
        items = [{'apiVersion': i['apiVersion'], 'kind': i['kind'],
                  'metadata': {k: i['metadata'][k] for k in ('name', 'namespace')}} for i in items]
    json.dump({'apiVersion': 'v1', 'kind': 'List', 'items': items}, sys.stdout)


if __name__ == '__main__':
    main()
