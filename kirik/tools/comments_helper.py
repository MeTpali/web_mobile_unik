import ast
import io
import re
import tokenize

def remove_python_comments(text):
    lines = text.splitlines(keepends=True)
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line))
    spans = []
    for token in tokenize.generate_tokens(io.StringIO(text).readline):
        if token.type == tokenize.COMMENT:
            spans.append((offsets[token.start[0] - 1] + token.start[1], offsets[token.end[0] - 1] + token.end[1]))
    # AST отличает настоящий docstring от строкового литерала в рабочем коде.
    for node in ast.walk(ast.parse(text)):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)) and node.body:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
                start = offsets[first.lineno - 1] + len(lines[first.lineno - 1].encode()[:first.col_offset].decode())
                end = offsets[first.end_lineno - 1] + len(lines[first.end_lineno - 1].encode()[:first.end_col_offset].decode())
                spans.append((start, end))
    for start, end in sorted(spans, reverse=True):
        text = text[:start] + ''.join('\n' if c == '\n' else ' ' for c in text[start:end]) + text[end:]
    ast.parse(text)
    return text

def remove_c_comments(text):
    # Лексический проход сохраняет URL, escape-последовательности и строки SQL.
    output, index = [], 0
    while index < len(text):
        char = text[index]
        if char in ('"', "'", '`'):
            quote = char
            output.append(char); index += 1
            while index < len(text):
                char = text[index]; output.append(char); index += 1
                if char == '\\' and index < len(text):
                    output.append(text[index]); index += 1
                elif char == quote:
                    break
        elif text.startswith('//', index):
            end = text.find('\n', index)
            index = len(text) if end < 0 else end
        elif text.startswith('/*', index) or text.startswith('<!--', index):
            end_marker = '*/' if text.startswith('/*', index) else '-->'
            end = text.find(end_marker, index)
            end = len(text) if end < 0 else end + len(end_marker)
            output.append(''.join('\n' if c == '\n' else ' ' for c in text[index:end]))
            index = end
        else:
            output.append(char); index += 1
    return ''.join(output)

