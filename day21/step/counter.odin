package step

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

Plot_Error :: union {
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
		fmt.printf("Usage: %s <file> [<times>]\n", os.args[0])
		os.exit(1)
	}
	filename := arguments[0]
	steps := 64
	if len(arguments) > 1 do steps = strconv.atoi(arguments[1])

	time_start := time.tick_now()
	part1, part2, error := process_file(filename, steps)
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

process_file :: proc(
	filename: string,
	steps: int = 64,
) -> (
	part1: int,
	part2: int,
	err: Plot_Error,
) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	if lines[len(lines) - 1] == "" do lines = lines[0:len(lines) - 1]

	garden := parse_garden(lines)
	defer delete(garden)
	defer for p in garden do delete(p)

	for i := 0; i < steps; i += 1 {
		take_a_step(garden)
		reset_steps(garden)
	}

	print_garden(garden)

	part1 = count_plots(garden)

	return
}

parse_garden :: proc(lines: []string) -> (garden: [][]u8) {
	garden = make([][]u8, len(lines))
	for i := 0; i < len(lines); i += 1 {
		garden[i] = make([]u8, len(lines[0]))
		for j := 0; j < len(lines[0]); j += 1 {
			garden[i][j] = lines[i][j]
		}
	}

	return
}

print_garden :: proc(garden: [][]u8) {
	for i := 0; i < len(garden); i += 1 {
		for j := 0; j < len(garden[0]); j += 1 {
			fmt.printf("%c", garden[i][j])
		}
		fmt.println("")
	}
}

count_plots :: proc(garden: [][]u8) -> (count: int) {
	for i := 0; i < len(garden); i += 1 {
		count += slice.count(garden[i], 'O')
		count += slice.count(garden[i], 'S')
	}

	return
}

reset_steps :: proc(garden: [][]u8) {
	for i := 0; i < len(garden); i += 1 {
		for j := 0; j < len(garden[0]); j += 1 {
			if garden[i][j] == 'S' do garden[i][j] = '.'
			if garden[i][j] == 'O' do garden[i][j] = 'S'
		}
	}
}

is_valid :: proc(i, j, max_row, max_col: int) -> bool {
	return i >= 0 && j >= 0 && i < max_row && j < max_col
}

take_a_step :: proc(garden: [][]u8) {
	for i := 0; i < len(garden); i += 1 {
		for j := 0; j < len(garden[0]); j += 1 {
			switch garden[i][j] {
			case 'S':
				if is_valid(i - 1, j, len(garden), len(garden[0])) {
					if garden[i - 1][j] != '#' {
						garden[i - 1][j] = 'O'
					}
				}
				if is_valid(i + 1, j, len(garden), len(garden[0])) {
					if garden[i + 1][j] != '#' {
						garden[i + 1][j] = 'O'
					}
				}
				if is_valid(i, j - 1, len(garden), len(garden[0])) {
					if garden[i][j - 1] != '#' {
						garden[i][j - 1] = 'O'
					}
				}
				if is_valid(i, j + 1, len(garden), len(garden[0])) {
					if garden[i][j + 1] != '#' {
						garden[i][j + 1] = 'O'
					}
				}
			case:
			}
		}
	}
}

