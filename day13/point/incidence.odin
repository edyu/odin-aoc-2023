package point

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Mirror_Error :: union {
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

Pattern :: struct {
	lines: []string,
}

process_file :: proc(filename: string) -> (part1: int, part2: int, err: Mirror_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	patterns := parse_patterns(lines)
	defer delete(patterns)
	defer for p in patterns do delete(p.lines)

	for p in patterns {
		fmt.println(p)
		h, v := find_reflection(p)
		fmt.printf("h: %d, v: %d\n", h, v)
		part1 += 100 * h + v
	}

	return part1, part2, nil
}

compare_column :: proc(pattern: Pattern, a, b: int) -> bool {
	for i := 0; i < len(pattern.lines); i += 1 {
		if pattern.lines[i][a] != pattern.lines[i][b] {
			return false
		}
	}
	return true
}

find_reflection :: proc(pattern: Pattern) -> (h, v: int) {
	p := 0
	for i := 1; i < len(pattern.lines); i += 1 {
		fmt.println("comparing:", p, i)
		if pattern.lines[i] == pattern.lines[p] {
			fmt.println("maybe:", p, i)
			n := min(len(pattern.lines) - i, p + 1)
			fmt.println("range:", n)
			checked := true
			for k in 1 ..< n {
				if pattern.lines[p - k] != pattern.lines[i + k] {
					fmt.println(pattern.lines[p - k], pattern.lines[i + k])
					checked = false
					break
				}
			}
			if checked {
				fmt.println("mirror:", p, i)
				h = p + 1
				break
			} else {
				fmt.println("not mirror:", p, i)
			}
		}
		p = i
	}
	p = 0
	for j := 1; j < len(pattern.lines[0]); j += 1 {
		if compare_column(pattern, p, j) {
			n := min(len(pattern.lines[0]) - j, p + 1)
			checked := true
			for k in 1 ..< n {
				if !compare_column(pattern, p - k, j + k) {
					checked = false
					break
				}
			}
			if checked {
				v = p + 1
				break
			}
		}
		p = j
	}

	return h, v
}

parse_patterns :: proc(lines: []string) -> (pattern_slice: []Pattern) {
	patterns: [dynamic]Pattern

	for i := 0; i < len(lines); i += 1 {
		j := i + 1
		for ; j < len(lines); j += 1 {
			if lines[j] == "" {
				pattern: Pattern
				pattern.lines = make([]string, j - i)
				for l, k in lines[i:j] {
					pattern.lines[k] = l
				}
				append(&patterns, pattern)
				break
			}
		}
		i = j
	}

	return patterns[:]
}

