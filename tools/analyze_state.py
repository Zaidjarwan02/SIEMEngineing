import sys

path = sys.argv[1] if len(sys.argv) > 1 else 'docs_snapshot2.txt'
s = open(path, encoding='utf-8', errors='replace').read()

if 'snapshot' in path:
    keys = ('"status" :', 'unassigned_shards', 'active_shards"', 'cluster_name',
            'number_of_nodes', 'space ', 'dashboards:', 'total:', 'heap.percent',
            'data view', '->')
    for line in s.splitlines():
        t = line.strip()
        if any(k in t for k in keys):
            print(t)
else:
    names = ['HARDWARE / RESOURCES', 'FAILED UNITS', 'PORTS OF INTEREST (PROBE)',
             'SECURITY POSTURE', 'LOGS (RECENT ERRORS)']
    for name in names:
        i = s.find('========== ' + name + ' ==========')
        if i < 0:
            print('MISSING BLOCK:', name)
            continue
        j = s.find('==========', i + 12)
        body = s[i:j if j > 0 else len(s)]
        print(body[:3500])
        print()
