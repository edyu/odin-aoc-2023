package lavaduct

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

Lagoon_Error :: union {
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

plan := map[u8]Direction {
	'D' = .Down,
	'R' = .Right,
	'U' = .Up,
	'L' = .Left,
}

step := [Direction][2]int {
	.Up = {-1, 0},
	.Left = {0, -1},
	.Down = {1, 0},
	.Right = {0, 1},
}

process_file :: proc(filename: string) -> (part1: int, part2: int, err: Lagoon_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	if lines[len(lines) - 1] == "" do lines = lines[0:len(lines) - 1]

	trench := dig_trench(lines)
	defer delete(trench)
	defer for r in trench do delete(r)
	volume1, interior := dig_interior(trench)
	defer delete(interior)
	defer for r in interior do delete(r)
	print_trench(interior)

	return volume1, part2, nil
}

dig_trench :: proc(lines: []string) -> (trench: [][]bool) {
	// make a guess how big the grid is
	ground := make([dynamic][dynamic]bool, len(lines) * 2)
	defer delete(ground)
	for i := 0; i < len(ground); i += 1 {
		ground[i] = make([dynamic]bool, len(lines) * 2)
	}
	defer for r in ground do delete(r)

	r := len(lines)
	c := len(lines)
	min_row := r
	min_col := c
	max_row := r + 1
	max_col := c + 1
	for l in lines {
		dir := plan[l[0]]
		i := 2
		j := 3
		for ; l[j] != ' '; j += 1 {
		}
		meters := strconv.atoi(l[i:j])

		ground[r][c] = true
		for k := 1; k < meters; k += 1 {
			r += step[dir].x
			c += step[dir].y

			ground[r][c] = true
		}
		r += step[dir].x
		c += step[dir].y
		if r < min_row do min_row = r
		if c < min_col do min_col = c
		if r > max_row do max_row = r + 1
		if c > max_col do max_col = c + 1
	}
	fmt.println("rows:", min_row, max_row)
	fmt.println("cols:", min_col, max_col)
	trench = make([][]bool, max_row - min_row + 2)
	trench[0] = make([]bool, max_col - min_col + 2)
	trench[len(trench) - 1] = make([]bool, max_col - min_col + 2)
	for i := 1; i < max_row - min_row + 1; i += 1 {
		// add extra at the end
		trench[i] = make([]bool, max_col - min_col + 2)
		for j := 1; j < max_col - min_col + 1; j += 1 {
			trench[i][j] = ground[min_row + i - 1][min_col + j - 1]
		}
	}
	print_trench(trench)

	return trench
}

dig_interior :: proc(trench: [][]bool) -> (volume: int, interior: [][]bool) {
	fmt.println("[2][2]:", trench[2][2])
	interior = make([][]bool, len(trench) - 2)
	for i := 1; i < len(trench) - 1; i += 1 {
		j := 1
		inside: bool
		pre: Direction
		interior[i - 1] = make([]bool, len(trench[0]) - 2)
		for j < len(trench[0]) - 1 {
			if trench[i][j] {
				interior[i - 1][j - 1] = true
				volume += 1
				if j + 1 == len(trench[0]) do break
				if trench[i][j + 1] { 	// not a single #
					if trench[i - 1][j] do pre = .Up
					else if trench[i + 1][j] do pre = .Down
					k := j + 1
					for ; k < len(trench[0]); k += 1 {
						if trench[i][k] {
							interior[i - 1][k - 1] = true
							volume += 1
						} else {
							break
						}
					}
					if (trench[i - 1][k - 1] && pre == .Up) ||
					   (trench[i + 1][k - 1] && pre == .Down) {
						// same
					} else {
						inside = !inside
					}
					j = k
				} else {
					j += 1
					inside = !inside
				}
			} else {
				if inside {
					interior[i - 1][j - 1] = true
					volume += 1
				}
				j += 1
			}
		}
	}

	return volume, interior
}

print_trench :: proc(trench: [][]bool) {
	for r := 0; r < len(trench); r += 1 {
		for c := 0; c < len(trench[0]); c += 1 {
			if trench[r][c] do fmt.print("#")
			else do fmt.print(".")
		}
		fmt.println("")
	}
}

