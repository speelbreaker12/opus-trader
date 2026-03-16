import json, sys

path = sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/claude-501/-Users-admin-Desktop-opus-trader/b454623b-45ed-4e05-a7a0-428fdee53477/tasks/aa26457967aac87c9.output"

with open(path) as f:
    lines = f.readlines()

# Extract all text from assistant messages (including text blocks mixed with tool_use)
all_text = ""
for line in lines:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'assistant':
            content = obj.get('message', {}).get('content', [])
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get('type') == 'text':
                        all_text += item.get('text', '')
    except:
        pass

print("Total assistant text:", len(all_text))
print("PREMORTEM markers:", all_text.count('PREMORTEM:'))
print()

# Also look at user messages containing tool results
tool_result_text = ""
for line in lines:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'user':
            content = obj.get('message', {}).get('content', [])
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get('type') == 'tool_result':
                        for sub in item.get('content', []):
                            if isinstance(sub, dict) and sub.get('type') == 'text':
                                tool_result_text += sub.get('text', '')
    except:
        pass

print("Tool result text:", len(tool_result_text))
print("PREMORTEM in tool results:", tool_result_text.count('PREMORTEM:'))

# Show last assistant text chunk
chunks = [c for c in all_text.split('\n') if c.strip()]
if chunks:
    print()
    print("Last 500 chars of assistant text:")
    print(all_text[-500:])
