import json

path = "/private/tmp/claude-501/-Users-admin-Desktop-opus-trader/b454623b-45ed-4e05-a7a0-428fdee53477/tasks/aa26457967aac87c9.output"

with open(path) as f:
    lines = f.readlines()

# Check user messages (tool results)
for i, line in enumerate(lines[:35]):
    line_s = line.strip()
    if not line_s:
        continue
    try:
        obj = json.loads(line_s)
        if obj.get('type') == 'user':
            content = obj.get('message', {}).get('content', [])
            print(f"Line {i}: user message, content type: {type(content).__name__}, len: {len(content) if isinstance(content, list) else 'n/a'}")
            if isinstance(content, list) and content:
                first = content[0]
                print(f"  first content type: {first.get('type', 'unknown') if isinstance(first, dict) else type(first)}")
                if isinstance(first, dict):
                    print(f"  first content keys: {list(first.keys())[:10]}")
                    # Check if it's a tool result
                    if 'tool_use_id' in first or first.get('type') == 'tool_result':
                        sub_content = first.get('content', [])
                        print(f"  sub_content type: {type(sub_content).__name__}, len: {len(sub_content) if isinstance(sub_content, list) else 'str_len:'+str(len(sub_content))}")
                        if isinstance(sub_content, list) and sub_content:
                            print(f"  sub_content[0]: {sub_content[0] if isinstance(sub_content[0], str) else list(sub_content[0].keys()) if isinstance(sub_content[0], dict) else sub_content[0]}")
                        elif isinstance(sub_content, str):
                            print(f"  sub_content str len: {len(sub_content)}")
            print()
    except Exception as e:
        pass
