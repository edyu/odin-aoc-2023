package boat

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

History_Error :: union {
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
	allocator_storage := make([]u8, 8 * mem.Megabyte)
	arena: mem.Arena
	mem.arena_init(&arena, allocator_storage)
	allocator := mem.arena_allocator(&arena)
	context.allocator = allocator
	context.temp_allocator = allocator
	// track: mem.Tracking_Allocator
	// mem.tracking_allocator_init(&track, context.allocator)
	// context.allocator = mem.tracking_allocator(&track)

	// defer {
	// 	if len(track.allocation_map) > 0 {
	// 		fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
	// 		for _, entry in track.allocation_map {
	// 			fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
	// 		}
	// 	}
	// 	if len(track.bad_free_array) > 0 {
	// 		fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
	// 		for entry in track.bad_free_array {
	// 			fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
	// 		}
	// 	}
	// 	mem.tracking_allocator_destroy(&track)
	// }
	arguments := os.args[1:]

	if len(arguments) < 1 {
		fmt.printf("Usage: mirage <file>\n")
		os.exit(1)
	}
	filename := arguments[0]

	time_start := time.now()
	part1, part2, error := process_file(filename)
	time_took := time.diff(time_start, time.now())
	memory_used := arena.peak_used
	if error != nil {
		fmt.eprintf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.printf("answer: part1 = %d part2 = %d\n", part1, part2)
	fmt.printf("time took %v\n", time_took)
	fmt.printf("memory used %v bytes\n", memory_used)
}

process_file :: proc(filename: string) -> (part1: int, part2: int, err: History_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)

	for l in lines {
		if l == "" do break
		part1 += predict_history(l)
		part2 += goback_history(l)
	}

	return part1, part2, nil
}

predict_history :: proc(line: string) -> (prediction: int) {
	string_values := strings.split(line, " ")
	defer delete(string_values)
	values := make([]int, len(string_values))
	defer delete(values)
	for v, i in string_values {
		values[i] = strconv.atoi(v)
	}

	prediction = find_next(values)
	return
}

find_next :: proc(values: []int) -> (next: int) {
	step := make([]int, len(values) - 1)
	defer delete(step)
	last := values[len(values) - 1]
	done: bool
	for i in 0 ..< len(values) - 1 {
		step[i] = values[i + 1] - values[i]
		if step[i] == 0 do done = true
		else do done = false
	}
	if done do next = last
	else do next = last + find_next(step)
	return
}

goback_history :: proc(line: string) -> (lookback: int) {
	string_values := strings.split(line, " ")
	defer delete(string_values)
	values := make([]int, len(string_values))
	defer delete(values)
	for v, i in string_values {
		values[i] = strconv.atoi(v)
	}

	lookback = find_previous(values)
	return
}

find_previous :: proc(values: []int) -> (previous: int) {
	step := make([]int, len(values) - 1)
	defer delete(step)
	first := values[0]
	done: bool
	for i in 0 ..< len(values) - 1 {
		step[i] = values[i + 1] - values[i]
		if step[i] == 0 do done = true
		else do done = false
	}
	if done do previous = first
	else do previous = first - find_previous(step)
	return
}

