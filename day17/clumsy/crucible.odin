package clumsy

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

opposite := [Direction]Direction {
	.Up    = .Down,
	.Left  = .Right,
	.Down  = .Up,
	.Right = .Left,
}

neighbors := [Direction][2]int {
	.Up = {-1, 0},
	.Left = {0, -1},
	.Down = {1, 0},
	.Right = {0, 1},
}

Node :: struct {
	row, col: int,
	w:        int,
	dir:      [3]Direction,
	// f:        int, // total cost of node
	// g:        int, // distance to start node
	// h:        int, // estimated distance to end node
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
	// closed_list: [dynamic]Node
	// defer delete(closed_list)
	row_len := len(lines)
	col_len := len(lines[0])
	g_score := make(map[Node]int)
	defer delete(g_score)
	f_score := make(map[Node]int)
	defer delete(f_score)
	came_from := make(map[Node]Node)
	defer delete(came_from)

	start := Node {
		row = 0,
		col = 0,
		w   = 0,
	}
	g_score[start] = 0
	f_score[start] = get_heuristic(start, row_len, col_len)

	append(&open_list, start)

	heat1, path1 := find_path_a_star(
		lines,
		&g_score,
		&f_score,
		&open_list,
		&came_from,
	)
	// path1 := get_path(closed_list)
	defer delete(path1)

	print_path(lines, path1)
	part1 = heat1
	// if right1 < down1 {
	// 	print_path(lines, path1)
	// } else {
	// 	print_path(lines, path2)
	// }
	// print_path(lines, path2)

	// part1 = min(right1, down1)

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

get_heuristic :: proc(node: Node, max_row, max_col: int) -> int {
	// manhattan distance is admissable because it never overestimates 
	return (max_row - 1 - node.row) + (max_col - 1 - node.col)
}

reconstruct_path :: proc(
	came_from: map[Node]Node,
	current: Node,
) -> (
	path: [dynamic]Node,
) {
	node := current
	append(&path, current)
	for (node in came_from) {
		node = came_from[node]
		inject_at(&path, 0, node)
	}
	return path
}

get_path :: proc(closed_list: [dynamic]Node) -> (path: [dynamic]Node) {
	end := closed_list[len(closed_list) - 1]
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
	for n in nodes[1:] {
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
	g_score: ^map[Node]int,
	f_score: ^map[Node]int,
	open_list: ^[dynamic]Node,
	came_from: ^map[Node]Node,
) -> (
	heat: int,
	path: [dynamic]Node,
) {
	for len(open_list) > 0 {
		lowest := 0
		for i := 1; i < len(open_list); i += 1 {
			low_node := open_list[lowest]
			node := open_list[i]
			if f_score[node] < f_score[low_node] {
				lowest = i
			}
		}
		current := open_list[lowest]
		// fmt.printf("open %v\n", open_list^)
		// fmt.printf("curent[%d][%d]=%v\n", current.row, current.col, current)
		// fmt.printf(
		// 	"curent[%d][%d].g=%d\n",
		// 	current.row,
		// 	current.col,
		// 	g_score[current],
		// )

		row_len := len(lines)
		col_len := len(lines[0])

		if current.row == row_len - 1 && current.col == col_len - 1 {
			return g_score[current], reconstruct_path(came_from^, current)
		}

		ordered_remove(open_list, lowest)

		for dir in Direction {
			if current.row == 0 && current.col == 0 {
				// starting node cannot go up or left
				if dir == .Up || dir == .Left do continue
			} else {
				// cannot backtrack
				if dir == opposite[current.dir[0]] {
					continue
				}
				// cannot be same direction more than 3 steps
				if slice.all_of(current.dir[:], dir) {
					continue
				}
			}

			offsets := neighbors[dir]
			row := current.row + offsets.x
			col := current.col + offsets.y

			// out of bounds
			if row < 0 || col < 0 || row == row_len || col == col_len {
				continue
			}

			w := int(lines[row][col] - '0')
			tentative_g := g_score[current] + w
			neighbor := Node {
				row = row,
				col = col,
				w   = w,
			}
			neighbor.dir[0] = dir
			if current.row == 0 && current.col == 0 {
				neighbor.dir[1] = dir
				neighbor.dir[2] = .Down if dir == .Right else .Right
			} else {
				neighbor.dir[1] = current.dir[0]
				neighbor.dir[2] = current.dir[1]
			}
			if !slice.contains(open_list[:], neighbor) {
				// not on open list
				if !(neighbor in g_score) do g_score[neighbor] = 1000000
				if !(neighbor in f_score) do f_score[neighbor] = 1000000
				if tentative_g < g_score[neighbor] {
					came_from[neighbor] = current
					g_score[neighbor] = tentative_g
					f_score[neighbor] =
						tentative_g + get_heuristic(neighbor, row_len, col_len)
					append(open_list, neighbor)
				}
			} else {
				if tentative_g < g_score[neighbor] { 	// better g
					came_from[neighbor] = current
					g_score[neighbor] = tentative_g
					f_score[neighbor] =
						tentative_g + get_heuristic(neighbor, row_len, col_len)
				}
			}
		}
	}
	return -1, nil
}
