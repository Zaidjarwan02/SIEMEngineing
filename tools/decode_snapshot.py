import re

data = open('docs_snapshot_raw.txt', 'rb').read()
try:
    text = data.decode('utf-16')
except Exception:
    text = data.decode('utf-8', 'replace')
text = text.replace('\x00', '')
open('docs_snapshot.txt', 'w', encoding='utf-8', newline='\n').write(text)

m = re.search(r'"status" : "(\w+)"', text)
print('cluster status:', m.group(1) if m else '?')
for line in text.splitlines():
    if any(k in line for k in ('unassigned_shards', 'space ', 'dashboards:', 'total:')):
        print(line.strip())
