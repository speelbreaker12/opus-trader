import json

path = "/private/tmp/claude-501/-Users-admin-Desktop-opus-trader/b454623b-45ed-4e05-a7a0-428fdee53477/tasks/aa26457967aac87c9.output"

with open(path) as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")

# Find tool calls and their names
for i, line in enumerate(lines):
    line_s = line.strip()
    if not line_s:
        continue
    try:
        obj = json.loads(line_s)
        if obj.get('type') == 'assistant':
            content = obj.get('message', {}).get('content', [])
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get('type') == 'tool_use':
                        tool_name = item.get('name', 'unknown')
                        tool_input = item.get('input', {})
                        # Show file path for Read calls, pattern for Grep
                        if tool_name == 'Read':
                            fp = tool_input.get('file_path', 'unknown')[:80]
                            print(f"  [{i}] {tool_name}: {fp}")
                        elif tool_name == 'Grep':
                            pat = tool_input.get('pattern', '')[:40]
                            pth = tool_input.get('path', '')[:40]
                            print(f"  [{i}] {tool_name}: pattern={pat}, path={pth}")
                        elif tool_name == 'Bash':
                            cmd = tool_input.get('command', '')[:60]
                            print(f"  [{i}] {tool_name}: {cmd}")
                        elif tool_name == 'Write':
                            fp = tool_input.get('file_path', 'unknown')[:80]
                            print(f"  [{i}] {tool_name}: {fp}")
                        else:
                            print(f"  [{i}] {tool_name}: {str(tool_input)[:60]}")
    except:
        pass
