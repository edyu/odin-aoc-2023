package clumsy

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Crucible_Error :: union {
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
			fmt.eprintf(
				"=== %v allocations not freed: ===\n",
				len(track.allocation_map),
			)
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		if len(track.bad_free_array) > 0 {
			fmt.eprintf(
				"=== %v incorrect frees: ===\n",
				len(track.bad_free_array),
			)
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

Node :: struct {
	row, col: int,
	dir:      Direction,
}

process_file :: proc(
	filename: string,
) -> (
	part1: int,
	part2: int,
	err: Crucible_Error,
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

	visited := make([]bool, len(lines) * len(lines[0]))
	defer delete(visited)
	visited2 := slice.clone(visited)
	defer delete(visited2)

	// right_heat, right_path := find_path(
	// 	lines,
	// 	&visited,
	// 	0,
	// 	len(lines),
	// 	len(lines[0]),
	// 	0,
	// 	0,
	// 	.Right,
	// 	nil,
	// 	nil,
	// )
	// defer delete(right_path)
	down_heat, down_path := find_path(
		lines,
		&visited2,
		0,
		len(lines),
		len(lines[0]),
		0,
		0,
		.Down,
		nil,
		nil,
	)
	defer delete(down_path)
	// fmt.println(right_heat, down_heat)
	// if right_heat < down_heat {
	// for p in right_path {
	// 	fmt.println(p)
	// }
	// } else {
	for p in down_path {
		fmt.println(p)
	}
	// }
	// part1 = min(right_heat, down_heat)
	part1 = down_heat

	return part1, part2, nil
}

find_path :: proc(
	lines: []string,
	visited: ^[]bool,
	current_heat: int,
	max_row, max_col, row, col: int,
	dir, dir2, dir3: Direction,
) -> (
	total_heat: int = 999999,
	path: [dynamic]Node,
) {
	if row < 0 || row >= max_row || col < 0 || col >= max_col do return 999999, nil

	if visited[row * max_col + col] do return 999999, nil
	visited[row * max_col + col] = true

	heat_loss := int(lines[row][col] - '0')

	// do no more
	if dir == .Up && row == 0 && col == max_col - 1 do return 999999, nil
	if dir == .Left && row == max_row - 1 && col == 0 do return 999999, nil

	heat := current_heat if row == 0 && col == 0 else current_heat + heat_loss

	node := Node {
		row = row,
		col = col,
		dir = dir,
	}
	if row == max_row - 1 && col == max_col - 1 {
		append(&path, node)
		return current_heat + heat_loss, path
	}

	// must change directions
	if (dir == dir2 && dir2 == dir3) ||
	   (dir == .Up && row == 0) ||
	   (dir == .Left && col == 0) ||
	   (dir == .Down && row == max_row - 1) ||
	   (dir == .Right && col == max_col - 1) {
		// need to change direction
		switch dir {
		case .Right:
			visited_up := slice.clone(visited^)
			defer delete(visited_up)
			heat_up, path_up := find_path(
				lines,
				&visited_up,
				heat,
				max_row,
				max_col,
				row - 1,
				col,
				.Up,
				dir,
				dir2,
			)
			visited_down := slice.clone(visited^)
			defer delete(visited_down)
			heat_down, path_down := find_path(
				lines,
				&visited_down,
				heat,
				max_row,
				max_col,
				row + 1,
				col,
				.Down,
				dir,
				dir2,
			)
			if heat_up < heat_down {
				delete(path_down)
				append(&path_up, node)
				total_heat = heat_up
				path = path_up
				set_visited(visited, visited_up)
			} else {
				delete(path_up)
				if heat_down != 999999 {
					append(&path_down, node)
					total_heat = heat_down
					path = path_down
					set_visited(visited, visited_down)
				}
			}
		case .Down:
			visited_left := slice.clone(visited^)
			defer delete(visited_left)
			heat_left, path_left := find_path(
				lines,
				&visited_left,
				heat,
				max_row,
				max_col,
				row,
				col - 1,
				.Left,
				dir,
				dir2,
			)
			visited_right := slice.clone(visited^)
			defer delete(visited_right)
			heat_right, path_right := find_path(
				lines,
				&visited_right,
				heat,
				max_row,
				max_col,
				row,
				col + 1,
				.Right,
				dir,
				dir2,
			)
			if heat_left < heat_right {
				delete(path_right)
				append(&path_left, node)
				total_heat = heat_left
				path = path_left
				set_visited(visited, visited_left)
			} else {
				delete(path_left)
				if heat_right != 999999 {
					append(&path_right, node)
					total_heat = heat_right
					path = path_right
					set_visited(visited, visited_right)
				}
			}
		case .Left:
			visited_down := slice.clone(visited^)
			defer delete(visited_down)
			heat_down, path_down := find_path(
				lines,
				&visited_down,
				heat,
				max_row,
				max_col,
				row + 1,
				col,
				.Down,
				dir,
				dir2,
			)
			append(&path_down, node)
			total_heat = heat_down
			path = path_down
			set_visited(visited, visited_down)
		case .Up:
			visited_right := slice.clone(visited^)
			defer delete(visited_right)
			heat_right, path_right := find_path(
				lines,
				&visited_right,
				heat,
				max_row,
				max_col,
				row,
				col + 1,
				.Right,
				dir,
				dir2,
			)
			if heat_right != 999999 {
				append(&path_right, node)
				total_heat = heat_right
				path = path_right
				set_visited(visited, visited_right)

			}
		}
	} else {
		switch dir {
		case .Right:
			visited_right := slice.clone(visited^)
			defer delete(visited_right)
			heat_right, path_right := find_path(
				lines,
				&visited_right,
				heat,
				max_row,
				max_col,
				row,
				col + 1,
				.Right,
				dir,
				dir2,
			)
			visited_up := slice.clone(visited^)
			defer delete(visited_up)
			heat_up, path_up := find_path(
				lines,
				&visited_up,
				heat,
				max_row,
				max_col,
				row - 1,
				col,
				.Up,
				dir,
				dir2,
			)
			visited_down := slice.clone(visited^)
			defer delete(visited_down)
			heat_down, path_down := find_path(
				lines,
				&visited_down,
				heat,
				max_row,
				max_col,
				row + 1,
				col,
				.Down,
				dir,
				dir2,
			)
			if heat_right < heat_up {
				if heat_right < heat_down {
					delete(path_up)
					delete(path_down)
					append(&path_right, node)
					total_heat = heat_right
					path = path_right
					set_visited(visited, visited_right)
				} else {
					delete(path_up)
					delete(path_right)
					if heat_down != 999999 {
						append(&path_down, node)
						total_heat = heat_down
						path = path_down
						set_visited(visited, visited_down)
					}
				}
			} else {
				if heat_up < heat_down {
					delete(path_right)
					delete(path_down)
					append(&path_up, node)
					total_heat = heat_up
					path = path_up
					set_visited(visited, visited_up)
				} else {
					delete(path_right)
					delete(path_up)
					if heat_down != 999999 {
						append(&path_down, node)
						total_heat = heat_down
						path = path_down
						set_visited(visited, visited_down)
					}
				}
			}
		case .Down:
			visited_down := slice.clone(visited^)
			defer delete(visited_down)
			heat_down, path_down := find_path(
				lines,
				&visited_down,
				heat,
				max_row,
				max_col,
				row + 1,
				col,
				.Down,
				dir,
				dir2,
			)
			visited_left := slice.clone(visited^)
			defer delete(visited_left)
			heat_left, path_left := find_path(
				lines,
				&visited_left,
				heat,
				max_row,
				max_col,
				row,
				col - 1,
				.Left,
				dir,
				dir2,
			)
			visited_right := slice.clone(visited^)
			defer delete(visited_right)
			heat_right, path_right := find_path(
				lines,
				&visited_right,
				heat,
				max_row,
				max_col,
				row,
				col + 1,
				.Right,
				dir,
				dir2,
			)
			if heat_down < heat_left {
				if heat_down < heat_right {
					delete(path_left)
					delete(path_right)
					append(&path_down, node)
					total_heat = heat_down
					path = path_down
					set_visited(visited, visited_down)
				} else {
					delete(path_left)
					delete(path_down)
					if heat_right != 999999 {
						append(&path_right, node)
						total_heat = heat_right
						path = path_right
						set_visited(visited, visited_right)
					}
				}
			} else {
				if heat_left < heat_right {
					delete(path_down)
					delete(path_right)
					append(&path_left, node)
					total_heat = heat_left
					path = path_left
					set_visited(visited, visited_left)
				} else {
					delete(path_down)
					delete(path_left)
					if heat_right != 999999 {
						append(&path_right, node)
						total_heat = heat_right
						path = path_right
						set_visited(visited, visited_right)
					}
				}
			}
		case .Left:
			visited_left := slice.clone(visited^)
			defer delete(visited_left)
			heat_left, path_left := find_path(
				lines,
				&visited_left,
				heat,
				max_row,
				max_col,
				row,
				col - 1,
				.Left,
				dir,
				dir2,
			)
			visited_down := slice.clone(visited^)
			defer delete(visited_down)
			heat_down, path_down := find_path(
				lines,
				&visited_down,
				heat,
				max_row,
				max_col,
				row + 1,
				col,
				.Down,
				dir,
				dir2,
			)
			if heat_left < heat_down {
				delete(path_down)
				append(&path_left, node)
				total_heat = heat_left
				path = path_left
				set_visited(visited, visited_left)
			} else {
				delete(path_left)
				append(&path_down, node)
				total_heat = heat_down
				path = path_down
				set_visited(visited, visited_down)
			}
		case .Up:
			visited_up := slice.clone(visited^)
			defer delete(visited_up)
			heat_up, path_up := find_path(
				lines,
				&visited_up,
				heat,
				max_row,
				max_col,
				row - 1,
				col,
				.Up,
				dir,
				dir2,
			)
			visited_right := slice.clone(visited^)
			defer delete(visited_right)
			heat_right, path_right := find_path(
				lines,
				&visited_right,
				heat,
				max_row,
				max_col,
				row,
				col + 1,
				.Right,
				dir,
				dir2,
			)
			if heat_up < heat_right {
				delete(path_right)
				append(&path_up, node)
				total_heat = heat_up
				path = path_up
				set_visited(visited, visited_up)
			} else {
				delete(path_up)
				if heat_right != 999999 {
					append(&path_right, node)
					total_heat = heat_right
					path = path_right
					set_visited(visited, visited_right)
				}
			}
		}
	}
	// fmt.printf(
	// 	"returning heat[%d][%d]=%d %v %v\n",
	// 	row,
	// 	col,
	// 	total_heat,
	// 	dir,
	// 	path,
	// )
	return total_heat, path
}

set_visited :: proc(visited: ^[]bool, new_visited: []bool) {
	for i := 0; i < len(visited); i += 1 {
		visited[i] = new_visited[i]
	}
}

print_map :: proc(energized: []bool, max_row, max_col: int) {
	for i := 0; i < max_row; i += 1 {
		for j := 0; j < max_col; j += 1 {
			if energized[i * max_col + j] do fmt.print("#")
			else do fmt.print(".")
		}
		fmt.println("")
	}
	fmt.println("")
}
