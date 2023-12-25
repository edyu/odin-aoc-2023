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
		fmt.printf("Usage: %s <file> [<steps> <steps2>]\n", os.args[0])
		os.exit(1)
	}
	filename := arguments[0]
	steps := 64
	steps2 := 26501365
	if len(arguments) > 1 do steps = strconv.atoi(arguments[1])
	if len(arguments) > 2 do steps2 = strconv.atoi(arguments[2])

	time_start := time.tick_now()
	part1, part2, error := process_file(filename, steps, steps2)
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
	steps2: int = 26501365,
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

	// print_garden(garden)

	part1 = count_plots(garden)

	fmt.println("part1:", part1)

	// plots: [dynamic][2]int
	// append(&plots, [2]int{0, 0})
	// for i := 0; i < steps2; i += 1 {
	// 	plots = step_garden(lines, plots)
	// 	// fmt.println(i, plots)
	// }
	// defer delete(plots)

	// part2 = len(plots)
	part2 = calculate_steps(lines, steps2, len(lines), len(lines) / 2)

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

get_plot :: proc(lines: []string, x, y: int) -> (plot: u8) {
	center_x := len(lines) / 2
	center_y := len(lines[0]) / 2

	coord_x := (x + center_x) % len(lines)
	coord_y := (y + center_y) % len(lines[0])
	if coord_x < 0 do coord_x += len(lines)
	if coord_y < 0 do coord_y += len(lines[0])

	return lines[coord_x][coord_y]
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

step_garden :: proc(lines: []string, current: [dynamic][2]int) -> (plots: [dynamic][2]int) {
	defer delete(current)

	for c in current {
		if get_plot(lines, c.x + 1, c.y) != '#' {
			plot := [2]int{c.x + 1, c.y}
			if !slice.contains(plots[:], plot) {
				append(&plots, plot)
			}
		}
		if get_plot(lines, c.x - 1, c.y) != '#' {
			plot := [2]int{c.x - 1, c.y}
			if !slice.contains(plots[:], plot) {
				append(&plots, plot)
			}
		}
		if get_plot(lines, c.x, c.y + 1) != '#' {
			plot := [2]int{c.x, c.y + 1}
			if !slice.contains(plots[:], plot) {
				append(&plots, plot)
			}
		}
		if get_plot(lines, c.x, c.y - 1) != '#' {
			plot := [2]int{c.x, c.y - 1}
			if !slice.contains(plots[:], plot) {
				append(&plots, plot)
			}
		}
	}

	return
}

get_steps :: proc(lines: []string, steps: int) -> (count: int) {
	plots: [dynamic][2]int
	append(&plots, [2]int{0, 0})
	for i := 0; i < steps; i += 1 {
		plots = step_garden(lines, plots)
	}
	defer delete(plots)

	return len(plots)
}

// use part1 to calculate steps after 65, 196, and 327 steps
// as it's 65 + n * 131 = 26501365 and n = 202300
calculate_steps :: proc(
	lines: []string,
	steps: int = 26501365,
	size: int = 131,
	edge: int = 65,
) -> (
	plots: int,
) {
	// 65
	// A :: 3884
	// 65 + 131 = 196 
	// B :: 34564
	// 65 + 2 * 131 = 327
	// C :: 95816
	A := get_steps(lines, 65)
	fmt.println("A:", A)
	B := get_steps(lines, 196)
	fmt.println("B:", B)
	C := get_steps(lines, 327)
	fmt.println("C:", C)

	a := (A - 2 * B + C) / 2
	fmt.println("a:", a)
	b := B - A - a
	fmt.println("b:", b)
	c := A
	fmt.println("c:", c)

	n := (steps - edge) / size
	fmt.println("n:", n)

	plots = a * n * n + b * n + c

	return plots
}

