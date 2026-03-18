import json

path = "/private/tmp/claude-501/-Users-admin-Desktop-opus-trader/b454623b-45ed-4e05-a7a0-428fdee53477/tasks/aa26457967aac87c9.output"

with open(path) as f:
    lines = f.readlines()

print("Total lines:", len(lines))

text_total = ""
for i, line in enumerate(lines):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        t = obj.get('type', '')
        if t == 'assistant':
            content = obj.get('message', {}).get('content', [])
            if isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get('type') == 'text':
                        text_total += c.get('text', '')
            elif isinstance(content, str):
                text_total += content
    except Exception as e:
        pass

print("Text extracted (JSONL method):", len(text_total))
print("First 200 chars:", repr(text_total[:200]))
print()

# Try alternate: find 'text' in all assistant objects
text_total2 = ""
for line in lines:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        t = obj.get('type', '')
        if 'assistant' in str(t):
            # Walk recursively looking for text content
            def extract_text(o):
                if isinstance(o, dict):
                    if o.get('type') == 'text' and 'text' in o:
                        return o['text']
                    return ''.join(extract_text(v) for v in o.values())
                elif isinstance(o, list):
                    return ''.join(extract_text(v) for v in o)
                return ''
            text_total2 += extract_text(obj)
    except:
        pass

print("Text extracted (recursive):", len(text_total2))
print("PREMORTEM markers:", text_total2.count('PREMORTEM:'))
