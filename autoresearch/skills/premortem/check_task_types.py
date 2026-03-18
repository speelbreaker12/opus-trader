import json
from collections import Counter

path = "/private/tmp/claude-501/-Users-admin-Desktop-opus-trader/b454623b-45ed-4e05-a7a0-428fdee53477/tasks/aa26457967aac87c9.output"

with open(path) as f:
    lines = f.readlines()

print("Total lines:", len(lines))

types = Counter()
for line in lines:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        types[obj.get('type', 'unknown')] += 1
    except:
        types['parse_error'] += 1

print("Types:", dict(types))
print()

# Look at non-user, non-assistant messages
for line in lines[:20]:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        t = obj.get('type', '')
        if t not in ('user',):
            keys = list(obj.keys())
            print(f"type={t}, keys={keys[:10]}")
            msg = obj.get('message', {})
            if msg:
                print(f"  message keys: {list(msg.keys())[:5]}")
                content = msg.get('content', [])
                if isinstance(content, list) and content:
                    print(f"  content[0] type: {content[0].get('type', 'unknown') if isinstance(content[0], dict) else type(content[0])}")
                    if isinstance(content[0], dict) and content[0].get('type') == 'text':
                        print(f"  text preview: {repr(content[0]['text'][:100])}")
    except Exception as e:
        print(f"Error: {e}")
    print()
