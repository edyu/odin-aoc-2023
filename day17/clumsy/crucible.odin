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
	w:        int,
	dir:      [3]Direction,
	f:        int, // total cost of node
	g:        int, // distance to start node
	h:        int, // estimated distance to end node
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

	open_list: [dynamic]Node
	defer delete(open_list)
	closed_list: [dynamic]Node
	defer delete(closed_list)
	w := int(lines[0][1] - '0')
	start := Node {
		row = 0,
		col = 1,
		w   = w,
		g   = w,
	}
	start.h = get_heuristic(start, len(lines), len(lines[0]))
	start.f = start.h + w
	start.dir[0] = .Right
	start.dir[1] = .Right
	start.dir[2] = .Down
	fmt.println(start)
	append(&open_list, start)
	right1 := find_path_a_star(lines, &open_list, &closed_list)
	path1 := get_path(closed_list)
	defer delete(path1)
	clear(&open_list)
	clear(&closed_list)
	w = int(lines[1][0] - '0')
	start = Node {
		row = 1,
		col = 0,
		w   = w,
		g   = w,
	}
	start.h = get_heuristic(start, len(lines), len(lines[0]))
	start.f = start.h + w
	start.dir[0] = .Down
	start.dir[1] = .Down
	start.dir[2] = .Right
	append(&open_list, start)
	down1 := find_path_a_star(lines, &open_list, &closed_list)
	path2 := get_path(closed_list)
	defer delete(path2)

	fmt.println("right:", right1, "down:", down1)

	print_path(lines, path1)
	// if right1 < down1 {
	// 	print_path(lines, path1)
	// } else {
	// 	print_path(lines, path2)
	// }

	part1 = min(right1, down1)

	return part1, part2, nil
}

in_list :: proc(list: [dynamic]Node, row, col: int, dir: Direction) -> int {
	for i := 0; i < len(list); i += 1 {
		if list[i].row == row && list[i].col == col && list[i].dir[0] == dir {
			return i
		}
	}
	return -1
}

in_open_list :: proc(list: [dynamic]Node, row, col: int) -> int {
	for i := 0; i < len(list); i += 1 {
		if list[i].row == row && list[i].col == col {
			return i
		}
	}
	return -1
}

get_heuristic :: proc(node: Node, max_row, max_col: int) -> int {
	// return node.w * ((max_row - 1 - node.row) + (max_col - 1 - node.col))
	// return(
	// 	(max_row - 1 - node.row) * (max_row - 1 - node.row) +
	// 	(max_col - 1 - node.col) * (max_col - 1 - node.col) \
	// )
	return (max_row - 1 - node.row) + (max_col - 1 - node.col)
}

get_path :: proc(closed_list: [dynamic]Node) -> (path: [dynamic]Node) {
	end := closed_list[len(closed_list) - 1]
	fmt.println("end", end)
	node := end
	for true {
		row := node.row
		col := node.col
		dir := node.dir[1]
		append(&path, node)
		if (row == 1 && col == 0) || (row == 0 && col == 1) do break
		switch node.dir[0] {
		case .Up:
			row += 1
		case .Down:
			row -= 1
		case .Left:
			col += 1
		case .Right:
			col -= 1
		}
		found := false
		node, found = find_node(closed_list, row, col, dir)
		if !found do break
	}
	return path
}

print_path :: proc(lines: []string, nodes: [dynamic]Node) {
	path := make([][]u8, len(lines))
	defer delete(path)
	defer for p in path do delete(p)
	for i := 0; i < len(lines); i += 1 {
		path[i] = make([]u8, len(lines[0]))
		for j := 0; j < len(lines[0]); j += 1 {
			path[i][j] = u8(lines[i][j])
		}
	}
	heat := 0
	for n in nodes {
		fmt.println(n)
		switch n.dir[0] {
		case .Up:
			path[n.row][n.col] = '^'
		case .Down:
			path[n.row][n.col] = 'v'
		case .Left:
			path[n.row][n.col] = '<'
		case .Right:
			path[n.row][n.col] = '>'
		}
		heat += n.w
	}
	for i := 0; i < len(lines); i += 1 {
		for j := 0; j < len(lines[0]); j += 1 {
			fmt.printf("%c", path[i][j])
		}
		fmt.println("")
	}
	fmt.println("heat loss:", heat)
}

find_node :: proc(
	closed_list: [dynamic]Node,
	row, col: int,
	dir: Direction,
) -> (
	node: Node,
	found: bool,
) {
	for n in closed_list {
		if n.row == row && n.col == col && n.dir[0] == dir {
			return n, true
		}
	}
	return node, false
}

find_path_a_star :: proc(
	lines: []string,
	open_list, closed_list: ^[dynamic]Node,
) -> int {
	for len(open_list) > 0 {
		lowest := 0
		for i := 1; i < len(open_list); i += 1 {
			if open_list[i].f < open_list[lowest].f {
				lowest = i
			} else if open_list[i].f == open_list[lowest].f {
				// lowest = i if open_list[i].h < open_list[lowest].h else lowest
				// fmt.println("found equal:", open_list[i], open_list[lowest])
			}
		}
		node := open_list[lowest]
		// fmt.printf("open %v\n", open_list^)
		fmt.printf("node[%d][%d]=%v\n", node.row, node.col, node)
		append(closed_list, node)
		ordered_remove(open_list, lowest)

		if node.row == len(lines) - 1 && node.col == len(lines[0]) - 1 {
			fmt.println("found end node")
			return node.g
		}

		if node.row - 1 >= 0 && node.dir[0] != .Down {
			if !slice.all_of(node.dir[:], Direction.Up) {
				j := in_list(closed_list^, node.row - 1, node.col, .Up)
				if j == -1 { 	// not on closed list
					k := in_list(open_list^, node.row - 1, node.col, .Up)
					w := int(lines[node.row - 1][node.col] - '0')
					g := node.g + w
					if k == -1 { 	// not on open list
						up := Node {
							row = node.row - 1,
							col = node.col,
							w   = w,
							g   = g,
						}
						up.dir[0] = .Up
						up.dir[1] = node.dir[0]
						up.dir[2] = node.dir[1]
						up.h = get_heuristic(up, len(lines), len(lines[0]))
						up.f = up.g + up.h
						fmt.println("adding up")
						append(open_list, up)
					} else if g < open_list[k].g { 	// better g
						fmt.println("found better", g, "for", open_list[k])
						open_list[k].g = g
						open_list[k].dir[0] = .Up
						open_list[k].dir[1] = node.dir[0]
						open_list[k].dir[2] = node.dir[1]
						open_list[k].f = g + open_list[k].h
					}
				}
			}
		}
		if node.col - 1 >= 0 && node.dir[0] != .Right {
			if !slice.all_of(node.dir[:], Direction.Left) {
				j := in_list(closed_list^, node.row, node.col - 1, .Left)
				if j == -1 { 	// not on closed list
					k := in_list(open_list^, node.row, node.col - 1, .Left)
					w := int(lines[node.row][node.col - 1] - '0')
					g := node.g + w
					if k == -1 { 	// not on open list
						left := Node {
							row = node.row,
							col = node.col - 1,
							w   = w,
							g   = g,
						}
						left.dir[0] = .Left
						left.dir[1] = node.dir[0]
						left.dir[2] = node.dir[1]
						left.h = get_heuristic(left, len(lines), len(lines[0]))
						left.f = left.g + left.h
						fmt.println("adding left")
						append(open_list, left)
					} else if g < open_list[k].g { 	// better g
						fmt.println("found better", g, "for", open_list[k])
						open_list[k].g = g
						open_list[k].dir[0] = .Left
						open_list[k].dir[1] = node.dir[0]
						open_list[k].dir[2] = node.dir[1]
						open_list[k].f = g + open_list[k].h
					}
				}
			}
		}
		if node.row + 1 < len(lines) && node.dir[0] != .Up {
			if !slice.all_of(node.dir[:], Direction.Down) {
				j := in_list(closed_list^, node.row + 1, node.col, .Down)
				if j == -1 { 	// not on closed list
					k := in_list(open_list^, node.row + 1, node.col, .Down)
					w := int(lines[node.row + 1][node.col] - '0')
					g := node.g + w
					if k == -1 { 	// not on open list
						down := Node {
							row = node.row + 1,
							col = node.col,
							w   = w,
							g   = g,
						}
						down.dir[0] = .Down
						down.dir[1] = node.dir[0]
						down.dir[2] = node.dir[1]
						down.h = get_heuristic(down, len(lines), len(lines[0]))
						down.f = down.g + down.h
						fmt.println("adding down")
						append(open_list, down)
					} else if g < open_list[k].g { 	// better g
						fmt.println("found better", g, "for", open_list[k])
						open_list[k].g = g
						open_list[k].dir[0] = .Down
						open_list[k].dir[1] = node.dir[0]
						open_list[k].dir[2] = node.dir[1]
						open_list[k].f = g + open_list[k].h
					}
				}
			}

		}
		if node.col + 1 < len(lines[0]) && node.dir[0] != .Left {
			if !slice.all_of(node.dir[:], Direction.Right) {
				j := in_list(closed_list^, node.row, node.col + 1, .Right)
				if j == -1 { 	// on closed list, ignore
					k := in_list(open_list^, node.row, node.col + 1, .Right)
					w := int(lines[node.row][node.col + 1] - '0')
					g := node.g + w
					if k == -1 { 	// not on open list
						right := Node {
							row = node.row,
							col = node.col + 1,
							w   = w,
							g   = g,
						}
						right.dir[0] = .Right
						right.dir[1] = node.dir[0]
						right.dir[2] = node.dir[1]
						right.h = get_heuristic(
							right,
							len(lines),
							len(lines[0]),
						)
						right.f = right.g + right.h
						fmt.println("adding right")
						append(open_list, right)
					} else if g < open_list[k].g { 	// better g
						fmt.println("found better", g, "for", open_list[k])
						open_list[k].g = g
						open_list[k].dir[0] = .Right
						open_list[k].dir[1] = node.dir[0]
						open_list[k].dir[2] = node.dir[1]
						open_list[k].f = g + open_list[k].h
					}
				}
			}
		}
	}
	return 0
}
