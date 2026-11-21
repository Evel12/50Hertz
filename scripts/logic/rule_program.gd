class_name RuleProgram
extends RefCounted

# Recursive descent over a tiny expression language. Never executes engine code.
var tokens: Array = []
var cursor := 0
var issue := ""
var variables: Array = []
var assignments: Dictionary = {}

func compile(source: String, sensors: Array, outputs: Array) -> String:
	assignments.clear()
	if source.length() > 4096: return "Line 1: program limit is 4096 characters"
	var depth := 0
	for ch in source:
		if ch == "(": depth += 1
		if ch == ")": depth -= 1
		if depth > 16: return "Line 1: maximum parenthesis depth is 16"
	variables = sensors
	var line_number := 0
	for raw in source.split("\n"):
		line_number += 1
		var line: String = raw.split("#")[0].strip_edges().to_upper()
		if line.is_empty(): continue
		var equal := line.find("=")
		if equal < 1: return "Line %d: expected OUTPUT = expression" % line_number
		var name := line.left(equal).strip_edges()
		if name not in outputs: return "Line %d: output %s is not permitted" % [line_number, name]
		if assignments.has(name): return "Line %d: duplicate driver for %s" % [line_number, name]
		issue = ""
		tokens = lex(line.substr(equal + 1))
		if tokens.size() > 256: return "Line %d: maximum 256 tokens per expression" % line_number
		cursor = 0
		var expression = parse_or()
		if cursor != tokens.size(): issue = "unexpected token " + str(tokens[cursor])
		if not issue.is_empty(): return "Line %d: %s" % [line_number, issue]
		assignments[name] = expression
	if assignments.is_empty(): return "Line 1: add at least one output assignment"
	return ""

func lex(line: String) -> Array:
	var result: Array = []
	var regex := RegEx.new()
	regex.compile("\\s*(>=|<=|==|!=|[()<>]|[A-Z_][A-Z_0-9]*|[0-9]+(?:\\.[0-9]+)?)")
	var offset := 0
	while offset < line.length():
		if line.substr(offset).strip_edges().is_empty(): break
		var found := regex.search(line, offset)
		if found == null or found.get_start() != offset:
			issue = "unsupported character near '" + line.substr(offset, 12) + "'"
			break
		result.append(found.get_string(1))
		offset = found.get_end()
	return result

func take(expected: String) -> bool:
	if cursor < tokens.size() and tokens[cursor] == expected:
		cursor += 1
		return true
	return false

func parse_or():
	var left = parse_and()
	while take("OR"): left = ["OR", left, parse_and()]
	return left

func parse_and():
	var left = parse_compare()
	while take("AND"): left = ["AND", left, parse_compare()]
	return left

func parse_compare():
	var left = parse_atom()
	if cursor < tokens.size() and tokens[cursor] in [">", "<", ">=", "<=", "==", "!="]:
		var op: String = tokens[cursor]
		cursor += 1
		return [op, left, parse_atom()]
	return left

func parse_atom():
	if take("NOT"): return ["NOT", parse_atom()]
	if take("("):
		var expression = parse_or()
		if not take(")"): issue = "missing closing parenthesis"
		return expression
	if cursor >= tokens.size():
		issue = "expected a sensor, constant or expression"
		return ["CONST", false]
	var token: String = tokens[cursor]
	cursor += 1
	if token in ["TRUE", "FALSE"]: return ["CONST", token == "TRUE"]
	if token.is_valid_float(): return ["CONST", float(token)]
	if token in variables: return ["VAR", token]
	issue = "unknown sensor " + token
	return ["CONST", false]

func value(tree: Array, sensors: Dictionary):
	match tree[0]:
		"CONST": return tree[1]
		"VAR": return sensors.get(tree[1], false)
		"NOT": return not bool(value(tree[1], sensors))
		"AND": return bool(value(tree[1], sensors)) and bool(value(tree[2], sensors))
		"OR": return bool(value(tree[1], sensors)) or bool(value(tree[2], sensors))
		">": return float(value(tree[1], sensors)) > float(value(tree[2], sensors))
		"<": return float(value(tree[1], sensors)) < float(value(tree[2], sensors))
		">=": return float(value(tree[1], sensors)) >= float(value(tree[2], sensors))
		"<=": return float(value(tree[1], sensors)) <= float(value(tree[2], sensors))
		"==": return value(tree[1], sensors) == value(tree[2], sensors)
		"!=": return value(tree[1], sensors) != value(tree[2], sensors)
	return false

func execute(sensors: Dictionary) -> Dictionary:
	var result := {}
	for output in assignments: result[output] = bool(value(assignments[output], sensors))
	return result
