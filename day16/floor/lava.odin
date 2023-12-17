package floor

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Beam_Error :: union {
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

Direction :: enum {
	Up,
	Left,
	Down,
	Right,
}

process_file :: proc(filename: string) -> (part1: int, part2: int, err: Beam_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	if lines[len(lines) - 1] == "" do lines = lines[0:len(lines) - 1]


	energized := make([]bool, len(lines) * len(lines[0]))
	defer delete(energized)
	energize_map := make(map[Beam]struct {})
	defer delete(energize_map)

	trace_beam(lines, energized, &energize_map, len(lines), len(lines[0]), 0, 0, .Right)
	// print_energy_map(energized, len(lines), len(lines[0]))
	part1 = slice.count(energized, true)

	for i := 0; i < len(lines); i += 1 {
		for &e in energized do e = false
		clear(&energize_map)
		trace_beam(lines, energized, &energize_map, len(lines), len(lines[0]), i, 0, .Right)
		energy := slice.count(energized, true)
		if energy > part2 do part2 = energy
	}
	for i := 0; i < len(lines); i += 1 {
		for &e in energized do e = false
		clear(&energize_map)
		trace_beam(
			lines,
			energized,
			&energize_map,
			len(lines),
			len(lines[0]),
			i,
			len(lines[0]) - 1,
			.Left,
		)
		energy := slice.count(energized, true)
		if energy > part2 do part2 = energy
	}
	for i := 0; i < len(lines[0]); i += 1 {
		for &e in energized do e = false
		clear(&energize_map)
		trace_beam(lines, energized, &energize_map, len(lines), len(lines[0]), 0, i, .Down)
		energy := slice.count(energized, true)
		if energy > part2 do part2 = energy
	}
	for i := 0; i < len(lines[0]); i += 1 {
		for &e in energized do e = false
		clear(&energize_map)
		trace_beam(
			lines,
			energized,
			&energize_map,
			len(lines),
			len(lines[0]),
			len(lines) - 1,
			i,
			.Up,
		)
		energy := slice.count(energized, true)
		if energy > part2 do part2 = energy
	}


	return part1, part2, nil
}

energize :: proc(energized: []bool, max_row, max_col, row, col: int) {
	energized[row * max_col + col] = true
}

Beam :: struct {
	row, col: int,
	dir:      Direction,
}

trace_beam :: proc(
	lines: []string,
	energized: []bool,
	energize_map: ^map[Beam]struct {},
	max_row, max_col, row, col: int,
	dir: Direction,
) {
	if row < 0 || row >= max_row || col < 0 || col >= max_col do return

	beam := Beam {
		row = row,
		col = col,
		dir = dir,
	}
	if beam in energize_map do return

	energize(energized, max_row, max_col, row, col)
	energize_map[beam] = {}

	switch lines[row][col] {
	case '.':
		switch dir {
		case .Up:
			trace_beam(lines, energized, energize_map, max_row, max_col, row - 1, col, dir)
		case .Left:
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col - 1, dir)
		case .Down:
			trace_beam(lines, energized, energize_map, max_row, max_col, row + 1, col, dir)
		case .Right:
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col + 1, dir)
		}
	case '|':
		switch dir {
		case .Up:
			trace_beam(lines, energized, energize_map, max_row, max_col, row - 1, col, .Up)
		case .Left:
			trace_beam(lines, energized, energize_map, max_row, max_col, row - 1, col, .Up)
			trace_beam(lines, energized, energize_map, max_row, max_col, row + 1, col, .Down)
		case .Down:
			trace_beam(lines, energized, energize_map, max_row, max_col, row + 1, col, .Down)
		case .Right:
			trace_beam(lines, energized, energize_map, max_row, max_col, row - 1, col, .Up)
			trace_beam(lines, energized, energize_map, max_row, max_col, row + 1, col, .Down)
		}
	case '\\':
		switch dir {
		case .Up:
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col - 1, .Left)
		case .Left:
			trace_beam(lines, energized, energize_map, max_row, max_col, row - 1, col, .Up)
		case .Down:
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col + 1, .Right)
		case .Right:
			trace_beam(lines, energized, energize_map, max_row, max_col, row + 1, col, .Down)
		}
	case '/':
		switch dir {
		case .Up:
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col + 1, .Right)
		case .Left:
			trace_beam(lines, energized, energize_map, max_row, max_col, row + 1, col, .Down)
		case .Down:
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col - 1, .Left)
		case .Right:
			trace_beam(lines, energized, energize_map, max_row, max_col, row - 1, col, .Up)
		}
	case '-':
		switch dir {
		case .Up:
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col - 1, .Left)
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col + 1, .Right)
		case .Left:
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col - 1, .Left)
		case .Down:
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col - 1, .Left)
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col + 1, .Right)
		case .Right:
			trace_beam(lines, energized, energize_map, max_row, max_col, row, col + 1, .Right)
		}
	}
}

print_energy_map :: proc(energized: []bool, max_row, max_col: int) {
	for i := 0; i < max_row; i += 1 {
		for j := 0; j < max_col; j += 1 {
			if energized[i * max_col + j] do fmt.print("#")
			else do fmt.print(".")
		}
		fmt.println("")
	}
	fmt.println("")
}

