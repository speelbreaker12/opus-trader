import json, re

with open('/Users/admin/.claude/projects/-Users-admin-Desktop-opus-trader/b454623b-45ed-4e05-a7a0-428fdee53477/subagents/agent-a9e4caeaf408fae07.jsonl') as f:
    lines = f.readlines()

text = ''
for line in lines:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'assistant':
            content = obj['message']['content']
            for c in content:
                if c.get('type') == 'text':
                    text += c['text']
    except:
        pass

# Find S5-003 section
start = text.find('PREMORTEM: S5-003')
if start == -1:
    start = text.find('Premortem: S5-003')
end = text.find('PREMORTEM: S3-015', start+1)
if end == -1:
    end = text.find('Premortem: S3-015', start+1)
if end == -1:
    end = start + 6000

t3 = text[start:end]
print('T3-A4 (debt register):', bool(re.search(r'(?i)debt\s+register', t3)))
print()

# Search for relevant keywords
for kw in ['Debt', 'debt', 'Register', 'register', 'Gap', 'gap_id', 'STOPLIGHT']:
    idx = t3.find(kw)
    if idx != -1:
        print(f'Found "{kw}" at {idx}: ...{repr(t3[max(0,idx-50):idx+100])}...')
        print()
