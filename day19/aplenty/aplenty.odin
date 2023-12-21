package aplenty

import pq "core:container/priority_queue"
import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Workflow_Error :: union {
	Unable_To_Read_File,
	Parse_Error,
	mem.Allocator_Error,
}

Parse_Error :: struct {
	reason: string,
}

Unable_To_Read_File :: struct {
	filename: string,
	error:    os.Errno,
}

main :: proc() {
	context.logger = log.create_console_logger()
	// allocator_storage := make([]u8, 8 * mem.Megabyte)
	// arena: mem.Arena
	// mem.arena_init(&arena, allocator_storage)
	// allocator := mem.arena_allocator(&arena)
	// context.allocator = allocator
	// context.temp_allocator = allocator
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		if len(track.bad_free_array) > 0 {
			fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
			for entry in track.bad_free_array {
				fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&track)
	}
	arguments := os.args[1:]

	if len(arguments) < 1 {
		fmt.printf("Usage: %s <file>\n", os.args[0])
		os.exit(1)
	}
	filename := arguments[0]

	time_start := time.tick_now()
	part1, part2, error := process_file(filename)
	time_took := time.tick_since(time_start)
	// memory_used := arena.peak_used
	if error != nil {
		fmt.eprintf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.printf("answer: part1 = %d part2 = %d\n", part1, part2)
	fmt.printf("time took %v\n", time_took)
	// fmt.printf("memory used %v bytes\n", memory_used)
}

Input :: map[rune]int

Rule :: struct {
	match:    rune,
	operator: Operator,
	name:     string,
	number:   int,
}

Operator :: enum {
	LT,
	GT,
	A,
	R,
	Next,
}

process_file :: proc(filename: string) -> (part1: int, part2: int, err: Workflow_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	if lines[len(lines) - 1] == "" do lines = lines[0:len(lines) - 1]

	workflows, parts := parse_workflow(lines)
	defer delete(workflows)
	defer for w in workflows do delete(workflows[w])
	defer delete(parts)
	defer for p in parts do delete(p)
	for p in parts {
		rating, accepted := run_workflow(workflows, p)
		if accepted do part1 += rating
	}

	return part1, part2, nil
}

parse_workflow :: proc(lines: []string) -> (workflows: map[string][]Rule, parts: []Input) {
	i := 0
	for ; i < len(lines) && lines[i] != ""; i += 1 {
		start_braces := strings.index_rune(lines[i], '{')
		name := lines[i][0:start_braces]
		rule_string := lines[i][start_braces + 1:len(lines[i]) - 1]
		rules := parse_rules(rule_string)
		workflows[name] = rules[:]
	}
	i += 1

	parts = parse_parts(lines[i:])[:]

	return
}

parse_rules :: proc(line: string) -> (rules: [dynamic]Rule) {
	rule_strings := strings.split(line, ",")
	defer delete(rule_strings)
	for rule_string in rule_strings {
		rule: Rule
		colon := strings.index_rune(rule_string, ':')
		if colon != -1 {
			rule.name = rule_string[colon + 1:]
			lt := strings.index_rune(rule_string, '<')
			if lt != -1 {
				rule.match = rune(rule_string[0])
				rule.operator = .LT
				rule.number = strconv.atoi(rule_string[lt + 1:])
			} else {
				rule.match = rune(rule_string[0])
				gt := strings.index_rune(rule_string, '>')
				assert(gt != -1)
				rule.operator = .GT
				rule.number = strconv.atoi(rule_string[gt + 1:])
			}
		} else {
			if rule_string == "A" {
				rule.operator = .A
			} else if rule_string == "R" {
				rule.operator = .R
			} else {
				rule.operator = .Next
				rule.name = rule_string
			}
		}
		append(&rules, rule)
	}
	return
}

parse_parts :: proc(lines: []string) -> (parts: [dynamic]Input) {
	for l in lines {
		line := l[1:len(l) - 1]
		input: Input
		tokens := strings.split_multi(line, []string{"=", ","})
		defer delete(tokens)

		for i := 0; i < len(tokens); i += 2 {
			input[rune(tokens[i][0])] = strconv.atoi(tokens[i + 1])
		}
		append(&parts, input)
	}
	return
}

rate_parts :: proc(part: Input) -> (rating: int) {
	for p in part {
		rating += part[p]
	}
	return rating
}

run_workflow :: proc(workflows: map[string][]Rule, part: Input) -> (rating: int, accepted: bool) {
	next := "in"

	for true {
		rules := workflows[next]
		inner: for rule in rules {
			switch rule.operator {
			case .A:
				return rate_parts(part), true
			case .R:
				return 0, false
			case .Next:
				next = rule.name
				break inner
			case .LT:
				if part[rule.match] < rule.number {
					if rule.name == "A" {
						return rate_parts(part), true
					} else if rule.name == "R" {
						return 0, false
					} else {
						next = rule.name
						break inner
					}
				}
			case .GT:
				if part[rule.match] > rule.number {
					if rule.name == "A" {
						return rate_parts(part), true
					} else if rule.name == "R" {
						return 0, false
					} else {
						next = rule.name
						break inner
					}
				}
			}
		}
	}
	return
}

