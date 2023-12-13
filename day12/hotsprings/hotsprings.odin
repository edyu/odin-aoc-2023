package hotsprings

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Hotspring_Error :: union {
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

Hotspring :: struct {
	record: string,
	groups: []int,
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

process_file :: proc(filename: string) -> (part1: int, part2: int, err: Hotspring_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	if lines[len(lines) - 1] == "" do lines = lines[0:len(lines) - 1]
	hotsprings := parse_hotsprings(lines) or_return
	defer delete(hotsprings)
	defer for h in hotsprings {
		delete(h.groups)
	}

	for h in hotsprings {
		fmt.println(h)
		sum := match_record(h) or_return
		fmt.printf("%v has %d arrangements\n", h, sum)
		part1 += sum
	}

	return part1, part2, nil
}

match_record :: proc(hotspring: Hotspring) -> (arrange: int, err: Hotspring_Error) {
	records := make([dynamic]string, 0, len(hotspring.groups))
	defer delete(records)
	for i := 0; i < len(hotspring.record); i += 1 {
		if len(records) >= len(hotspring.groups) do break
		if hotspring.record[i] == '.' do continue
		j := i + 1
		for ; j < len(hotspring.record); j += 1 {
			if hotspring.record[j] == '.' do break
		}
		append(&records, hotspring.record[i:j])
		i = j
	}
	return find_arrangements(records[:], hotspring.groups), nil
}

all_of :: proc(s: string, r: rune) -> bool {
	for v in s {
		if v != r do return false
	}
	return true
}

find_arrangements :: proc(records: []string, groups: []int) -> int {
	if len(records) == len(groups) {
		sum := 1
		for i in 0 ..< len(records) {
			if len(records[i]) != groups[i] {
				sum *= num_chosen(len(records[i]), groups[i])
			}
		}
		return sum
	}
	if len(records[0]) == groups[0] {
		return find_arrangements(records[1:], groups[1:])
	}
	if len(records[len(records) - 1]) == groups[len(groups) - 1] {
		return find_arrangements(records[0:len(records) - 1], groups[0:len(groups) - 1])
	}
	if len(records) == 1 {
		if all_of(records[0], '?') {
			return num_chosen(len(records[0]), math.sum(groups) + len(groups) - 1)
		} else {
			new_records := find_possible_records(groups, len(records[0]))
			defer delete(new_records)
			defer for r in new_records {
				delete(r)
			}
			fmt.printf("found %d possibilities\n", len(new_records))
			fmt.println(new_records)
		}
	}
	fmt.println("not implemented", records, groups)
	return 0
}

find_possible_records :: proc(groups: []int, length: int) -> (records: [dynamic]string) {
	record := strings.builder_make()
	for _ in 0 ..< groups[0] {
		strings.write_rune(&record, '#')
	}
	if len(groups) == 1 {
		for _ in 0 ..< length - groups[0] {
			strings.write_rune(&record, '.')
		}
		new_record := strings.to_string(record)
		append(&records, new_record)
		return records
	} else {
		strings.write_rune(&record, '.')
		suffix_base := math.sum(groups[1:]) + len(groups[1:]) - 1
		num_dots := length - (groups[0] + 1) - suffix_base
		defer strings.builder_destroy(&record)
		for i in 0 ..= num_dots {
			record_str := strings.to_string(record)
			dots := expand_dots(i)
			defer delete(dots)
			prefix := strings.concatenate([]string{record_str, dots})
			defer delete(prefix)
			suffices := find_possible_records(groups[1:], length - (groups[0] + 1) - i)
			defer delete(suffices)
			for s in suffices {
				new_record := strings.concatenate([]string{prefix, s})
				append(&records, new_record)
			}
			defer for s in suffices {
				delete(s)
			}
		}
	}
	return records
}

expand_dots :: proc(length: int) -> string {
	if length == 0 do return ""
	dots := strings.builder_make()
	for _ in 0 ..< length {
		strings.write_rune(&dots, '.')
	}
	return strings.to_string(dots)
}

num_chosen :: proc(m: int, n: int) -> int {
	return math.factorial(m) / (math.factorial(n) * math.factorial(m - n))
}

parse_hotsprings :: proc(lines: []string) -> (hotsprings: []Hotspring, err: Hotspring_Error) {
	hotsprings = make([]Hotspring, len(lines))

	fmt.printf("total of %d lines\n", len(lines))

	for line, i in lines {
		if line == "" do break
		fields := strings.split(line, " ") or_return
		defer delete(fields)
		string_groups := strings.split(fields[1], ",") or_return
		defer delete(string_groups)
		hotspring := Hotspring {
			record = fields[0],
		}
		groups := make([]int, len(string_groups))
		for j in 0 ..< len(string_groups) {
			groups[j] = strconv.atoi(string_groups[j])
		}
		hotspring.groups = groups
		hotsprings[i] = hotspring
	}

	return hotsprings, nil
}

