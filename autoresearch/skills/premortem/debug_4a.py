import json

path = "/private/tmp/claude-501/-Users-admin-Desktop-opus-trader/b454623b-45ed-4e05-a7a0-428fdee53477/tasks/aa26457967aac87c9.output"

with open(path) as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")

# Get last 5 lines
for line in lines[-5:]:
    line_s = line.strip()
    if not line_s:
        continue
    try:
        obj = json.loads(line_s)
        t = obj.get('type', 'unknown')
        if t == 'assistant':
            content = obj.get('message', {}).get('content', [])
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get('type') == 'text':
                        print(f"ASSISTANT TEXT: {repr(item['text'][:200])}")
                    elif isinstance(item, dict) and item.get('type') == 'tool_use':
                        print(f"TOOL_USE: {item.get('name')} - {str(item.get('input', {}))[:100]}")
        elif t == 'user':
            content = obj.get('message', {}).get('content', [])
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict):
                        if item.get('type') == 'tool_result':
                            subcontent = item.get('content', '')
                            if isinstance(subcontent, str):
                                print(f"TOOL_RESULT: {repr(subcontent[:100])}")
        elif t == 'progress':
            data = obj.get('data', '')
            print(f"PROGRESS: {repr(str(data)[:100])}")
    except Exception as e:
        print(f"Parse error: {e}")
    print()
