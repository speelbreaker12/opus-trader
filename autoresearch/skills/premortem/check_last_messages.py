import json

path = "/private/tmp/claude-501/-Users-admin-Desktop-opus-trader/b454623b-45ed-4e05-a7a0-428fdee53477/tasks/aa26457967aac87c9.output"

with open(path) as f:
    lines = f.readlines()

# Get ALL assistant messages and their content types
assistant_msgs = []
for i, line in enumerate(lines):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'assistant':
            content = obj.get('message', {}).get('content', [])
            content_types = [item.get('type', 'unknown') if isinstance(item, dict) else type(item).__name__ for item in content] if isinstance(content, list) else ['non-list']
            text_len = sum(len(item.get('text', '')) for item in content if isinstance(item, dict) and item.get('type') == 'text')
            assistant_msgs.append((i, content_types, text_len))
    except:
        pass

print(f"Total assistant messages: {len(assistant_msgs)}")
for idx, (line_num, ctypes, tlen) in enumerate(assistant_msgs):
    print(f"  [{idx+1}] line={line_num}, content_types={ctypes}, text_len={tlen}")
