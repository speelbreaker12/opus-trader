import json

path = "/private/tmp/claude-501/-Users-admin-Desktop-opus-trader/b454623b-45ed-4e05-a7a0-428fdee53477/tasks/aa26457967aac87c9.output"

with open(path) as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")

# Check the last 10 lines
for i, line in enumerate(lines[-10:]):
    line_s = line.strip()
    if not line_s:
        print(f"  line {len(lines)-10+i}: empty")
        continue
    try:
        obj = json.loads(line_s)
        t = obj.get('type', 'unknown')
        if t == 'assistant':
            content = obj.get('message', {}).get('content', [])
            content_types = [c.get('type') if isinstance(c, dict) else type(c).__name__ for c in content] if isinstance(content, list) else ['non-list']
            text_chunks = [c.get('text', '')[:100] for c in content if isinstance(c, dict) and c.get('type') == 'text']
            print(f"  line {len(lines)-10+i}: assistant, content_types={content_types}, texts={text_chunks}")
        elif t == 'user':
            content = obj.get('message', {}).get('content', [])
            if isinstance(content, list) and content and isinstance(content[0], dict):
                ct = content[0].get('type', 'unknown')
                print(f"  line {len(lines)-10+i}: user, content_type={ct}")
            elif isinstance(content, str):
                print(f"  line {len(lines)-10+i}: user, content=str, len={len(content)}")
        else:
            print(f"  line {len(lines)-10+i}: {t}")
    except Exception as e:
        print(f"  line {len(lines)-10+i}: parse error: {e}")
