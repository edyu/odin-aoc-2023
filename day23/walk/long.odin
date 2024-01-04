package walk

import q "core:container/queue"
import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Trail_Error :: union {
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

process_file :: proc(filename: string) -> (part1: int, part2: int, err: Trail_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	if lines[len(lines) - 1] == "" do lines = lines[0:len(lines) - 1]

	start := parse_start(lines[0])
	fmt.println("start:", start)

	empty: [dynamic]Coord
	path, found := longest_hike(lines, empty, start)
	defer delete(path)
	// fmt.println("path:", path)
	if found {
		fmt.println("end:", path[len(path) - 1])
		part1 = len(path) - 1
	}
	fmt.println("part1:", part1)

	path2: [dynamic]Coord
	defer delete(path2)
	length2, found2 := longest_climb(lines, &path2, start)
	// fmt.println("len2:", len(path2))
	if found2 {
		part2 = length2 - 1
	}
	fmt.println("path2:", path2)

	return
}

Coord :: [2]int

parse_start :: proc(line: string) -> (start: Coord) {
	for tile, col in line {
		if tile == '.' do return {0, col}
	}
	return
}

in_path :: proc(path1, path2: [dynamic]Coord, row, col: int) -> bool {
	if visited(path1, row, col) do return true
	if visited(path2, row, col) do return true

	return false
}

visited :: proc(path: [dynamic]Coord, row, col: int) -> bool {
	for p in path {
		if p.x == row && p.y == col do return true
	}
	return false
}

valid_tile :: proc(lines: []string, row, col: int) -> bool {
	return(
		row >= 0 &&
		col >= 0 &&
		row < len(lines) &&
		col < len(lines[0]) &&
		lines[row][col] != '#' \
	)
}

longest_hike :: proc(
	lines: []string,
	existing: [dynamic]Coord,
	current: Coord,
) -> (
	path: [dynamic]Coord,
	ok: bool,
) {
	append(&path, current)
	// found the end
	if current.x == len(lines) - 1 do return path, true
	paths: [dynamic][dynamic]Coord
	switch lines[current.x][current.y] {
	case '.':
		if valid_tile(lines, current.x - 1, current.y) &&
		   !in_path(path, existing, current.x - 1, current.y) {
			if remaining, ok := longest_hike(lines, path, {current.x - 1, current.y}); ok {
				append(&paths, remaining)
			} else {
				defer delete(remaining)
			}
		}
		if valid_tile(lines, current.x + 1, current.y) &&
		   !in_path(path, existing, current.x + 1, current.y) {
			if remaining, ok := longest_hike(lines, path, {current.x + 1, current.y}); ok {
				append(&paths, remaining)
			} else {
				defer delete(remaining)
			}
		}
		if valid_tile(lines, current.x, current.y - 1) &&
		   !in_path(path, existing, current.x, current.y - 1) {
			if remaining, ok := longest_hike(lines, path, {current.x, current.y - 1}); ok {
				append(&paths, remaining)
			} else {
				defer delete(remaining)
			}
		}
		if valid_tile(lines, current.x, current.y + 1) &&
		   !in_path(path, existing, current.x, current.y + 1) {
			if remaining, ok := longest_hike(lines, path, {current.x, current.y + 1}); ok {
				append(&paths, remaining)
			} else {
				defer delete(remaining)
			}
		}
	case '>':
		if valid_tile(lines, current.x, current.y + 1) &&
		   !in_path(path, existing, current.x, current.y + 1) {
			if remaining, ok := longest_hike(lines, path, {current.x, current.y + 1}); ok {
				append(&paths, remaining)
			} else {
				defer delete(remaining)
			}
		}
	case '^':
		if valid_tile(lines, current.x - 1, current.y) &&
		   !in_path(path, existing, current.x - 1, current.y) {
			if remaining, ok := longest_hike(lines, path, {current.x - 1, current.y}); ok {
				append(&paths, remaining)
			} else {
				defer delete(remaining)
			}
		}
	case '<':
		if valid_tile(lines, current.x, current.y - 1) &&
		   !in_path(path, existing, current.x, current.y - 1) {
			if remaining, ok := longest_hike(lines, path, {current.x, current.y - 1}); ok {
				append(&paths, remaining)
			} else {
				defer delete(remaining)
			}
		}
	case 'v':
		if valid_tile(lines, current.x + 1, current.y) &&
		   !in_path(path, existing, current.x + 1, current.y) {
			if remaining, ok := longest_hike(lines, path, {current.x + 1, current.y}); ok {
				append(&paths, remaining)
			} else {
				defer delete(remaining)
			}
		}
	}

	longest := 0
	index := -1
	for p, i in paths {
		if len(p) > longest {
			longest = len(p)
			index = i
		}
	}

	if index != -1 {
		for s in paths[index] {
			append(&path, s)
		}
		defer delete(paths)
		defer for p in paths do delete(p)
		return path, true
	} else do return path, false
}

longest_climb :: proc(
	lines: []string,
	sofar: ^[dynamic]Coord,
	start: Coord,
) -> (
	length: int,
	ok: bool,
) {
	current := start

	// found the end
	if current.x == len(lines) - 1 {
		append(sofar, current)
		return len(sofar^), true
	}

	possible_paths: [dynamic]Coord
	defer delete(possible_paths)
	if lines[current.x][current.y] != '#' {
		if valid_tile(lines, current.x - 1, current.y) &&
		   !visited(sofar^, current.x - 1, current.y) {
			append(&possible_paths, Coord{current.x - 1, current.y})
		}
		if valid_tile(lines, current.x + 1, current.y) &&
		   !visited(sofar^, current.x + 1, current.y) {
			append(&possible_paths, Coord{current.x + 1, current.y})
		}
		if valid_tile(lines, current.x, current.y - 1) &&
		   !visited(sofar^, current.x, current.y - 1) {
			append(&possible_paths, Coord{current.x, current.y - 1})
		}
		if valid_tile(lines, current.x, current.y + 1) &&
		   !visited(sofar^, current.x, current.y + 1) {
			append(&possible_paths, Coord{current.x, current.y + 1})
		}
	}

	switch len(possible_paths) {
	case 0:
		pop(sofar)
		return 0, false
	case 1:
		append(sofar, current)
		length, ok = longest_climb(lines, sofar, possible_paths[0])
		if ok {
			return length, ok
		} else {
			pop(sofar)
			return 0, false
		}
	case 2:
		fallthrough
	case 3:
		fallthrough
	case 4:
		longest := 0
		path: [dynamic]Coord

		append(sofar, current)

		for p in possible_paths {
			clone: [dynamic]Coord
			for s in sofar {
				append(&clone, s)
			}
			length, ok = longest_climb(lines, &clone, p)
			if ok && length > longest {
				longest = length
				delete(path)
				path = clone
			} else {
				defer delete(clone)
			}
		}
		if longest > 0 {
			// fmt.println("longest is", longest)
			defer delete(path)
			for i := len(sofar^); i < len(path); i += 1 {
				append(sofar, path[i])
			}
			return longest, true
		} else {
			pop(sofar)
			return 0, false
		}
	}

	return
}

