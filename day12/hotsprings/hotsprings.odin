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

State :: struct {
	record_index: int,
	groups_index: int,
	group_num: int,
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
		sum := match_record(h) or_return
		part1 += sum
	}

	hotsprings2 := parse_hotsprings(lines, false) or_return
	defer delete(hotsprings2)
	defer for h in hotsprings2 {
		delete(h.groups)
	}

	for h in hotsprings2 {
		sum := match_record2(h) or_return
		fmt.printf("%v has %d arrangements\n", h, sum)
		part2 += sum
	}

	return part1, part2, nil
}

match_record :: proc(hotspring: Hotspring) -> (arrange: int, err: Hotspring_Error) {
	return find_arrangements(hotspring.record, hotspring.groups), nil
}

states: map[State]int

match_record2 :: proc(hotspring: Hotspring) -> (arrange: int, err: Hotspring_Error) {
	states = make(map[State]int)
	defer delete(states)

	record := strings.join([]string { hotspring.record, hotspring.record,
		hotspring.record, hotspring.record, hotspring.record}, "?")
	defer delete(record)
	groups := make([]int, len(hotspring.groups) * 5)
	defer delete(groups)
	for i in 0 ..< 5 {
		for j in 0..<len(hotspring.groups) {
			groups[i * len(hotspring.groups) + j] = hotspring.groups[j]			
		}
	}
	new_record :=  strings.trim(record, ".")
	fmt.println("record:", new_record)
	fmt.println("groups:", groups)
	return count_arrangements(new_record, groups, 0, 0, 0), nil
}

all_of :: proc(s: string, r: rune) -> bool {
	for v in s {
		if v != r do return false
	}
	return true
}

// record_index indexes into the pattern
// groups_index indexes into the groups
// group_num is the number of '#' we have matched in the current group
count_arrangements :: proc(pattern: string, groups: []int, record_index, groups_index, group_num: int) -> (sum: int) {
	// check cache
    state := State{record_index, groups_index, group_num}
    cache, exists := states[state]
	if exists do return cache

	// all groups consumed
    if groups_index == len(groups) {
		if group_num != 0 || strings.contains_rune(pattern[record_index:], '#') {
			// we still have more bad groups in pattern; bad match
			return 0
		} else {
			return 1
		}
	}

    if group_num > groups[groups_index] {
		return 0
	}

	// pattern consumed
    if record_index == len(pattern) {
		// all consumed
		if (groups_index == len(groups) && group_num == 0) || (groups_index == len(groups) - 1 && group_num == groups[groups_index]) {
			return 1
		} else {
			// not done; bad match 
			return 0
		}
	}

    switch pattern[record_index] {
    case '#':
		// advance pattern and advance the number of '#' matched in group
        sum = count_arrangements(pattern, groups, record_index + 1, groups_index, group_num + 1)
    case '.':
        if group_num == 0 {
			// advance to next character in pattern
            sum = count_arrangements(pattern, groups, record_index + 1, groups_index, 0)
		} else if group_num == groups[groups_index] {
			// everything matched; work on next group
            sum = count_arrangements(pattern, groups, record_index + 1, groups_index + 1, 0)
        }
    case '?':
        if group_num == 0 {
			// pretend '?' is '#' or '.'
			// add the counts together
            sum = count_arrangements(pattern, groups, record_index + 1, groups_index, 0) + count_arrangements(pattern, groups, record_index + 1, groups_index, 1)
		} else {
            if group_num == groups[groups_index] {
				// already matched the current group
                sum = count_arrangements(pattern, groups, record_index + 1, groups_index + 1, 0)
            }
			// '?' is '#'
            sum += count_arrangements(pattern, groups, record_index + 1, groups_index, group_num + 1)
        }
    }
    states[state] = sum
    return sum
}

find_arrangements :: proc(pattern: string, groups: []int) -> (sum: int) {
	return generate_possible_records(pattern, groups, len(pattern))
}

fit_record :: proc(pattern: string, record: string) -> bool {
	assert(len(pattern) == len(record))
	for i in 0 ..< len(pattern) {
		if pattern[i] == record[i] do continue
		if pattern[i] == '#' do return false
		if pattern[i] == '.' do return false
	}
	return true
}

generate_possible_records :: proc(pattern: string, groups: []int, length: int) -> (count: int) {
	suffix_base := math.sum(groups) + len(groups) - 1

	if suffix_base == length {
		records := find_possible_records(groups, length)
		defer delete(records)
		for r in records {
			if fit_record(pattern, r) do count += 1
		}
		defer for r in records {
			delete(r)
		}
	} else {
		for i in 0 ..= length - suffix_base {
			dots := expand_dots(i)
			defer delete(dots)
			suffices := find_possible_records(groups, length - i)
			defer delete(suffices)
			for s in suffices {
				record := strings.concatenate([]string{dots, s})
				defer delete(record)
				if	fit_record(pattern, record) do count += 1
			}
			defer for s in suffices {
				delete(s)
			}
		}
	}

	return count
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

parse_hotsprings :: proc(lines: []string, trim: bool = true) -> (hotsprings: []Hotspring, err: Hotspring_Error) {
	hotsprings = make([]Hotspring, len(lines))

	for line, i in lines {
		if line == "" do break
		fields := strings.split(line, " ") or_return
		defer delete(fields)
		string_groups := strings.split(fields[1], ",") or_return
		defer delete(string_groups)
		hotspring := Hotspring {
			record = strings.trim(fields[0], ".")
		} if trim else Hotspring {
			record = fields[0]
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

