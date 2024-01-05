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
	path, _ := longest_hike(lines, empty, start)
	defer delete(path)
	// fmt.println("path:", path)
	end := path[len(path) - 1]
	fmt.println("end:", path[len(path) - 1])
	part1 = len(path) - 1
	fmt.println("part1:", part1)

	// path2: [dynamic]Coord
	// defer delete(path2)
	// length2, found2 := longest_climb(lines, &path2, start)
	// // fmt.println("len2:", len(path2))
	// if found2 {
	// 	part2 = length2 - 1
	// }
	// fmt.println("path2:", path2)

	cross, next := parse_cross_tiles(lines, start, end)
	defer delete(cross)
	defer delete(next)
	defer for n in next do delete(next[n])

	// fmt.println("cross:", cross)
	// fmt.println("next:", next)

	graph := create_graph(cross[:], next)
	defer delete(graph)
	defer for g in graph do delete(graph[g])

	// fmt.println("graph:", graph)

	visited := make(map[Coord]bool)
	defer delete(visited)
	visited[start] = true
	lengths := traverse(graph, start, end, &visited, 0)
	defer delete(lengths)
	part2 = slice.max(lengths[:])

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

parse_cross_tiles :: proc(
	lines: []string,
	start, end: Coord,
) -> (
	cross_tiles: [dynamic]Coord,
	next_tiles: map[Coord][]Coord,
) {
	append(&cross_tiles, start)
	append(&cross_tiles, end)
	next_tiles = make(map[Coord][]Coord)

	for i := 0; i < len(lines); i += 1 {
		for j := 0; j < len(lines[0]); j += 1 {
			if lines[i][j] != '#' {
				next: [dynamic]Coord
				if valid_tile(lines, i - 1, j) {
					append(&next, Coord{i - 1, j})
				}
				if valid_tile(lines, i + 1, j) {
					append(&next, Coord{i + 1, j})
				}
				if valid_tile(lines, i, j - 1) {
					append(&next, Coord{i, j - 1})
				}
				if valid_tile(lines, i, j + 1) {
					append(&next, Coord{i, j + 1})
				}
				next_tiles[Coord{i, j}] = next[:]
				if len(next) > 2 {
					append(&cross_tiles, Coord{i, j})
				}
			}
		}
	}

	return
}

calculate_distance :: proc(
	cross_tiles: []Coord,
	next_tiles: map[Coord][]Coord,
	cur_tile: Coord,
	cur_dist: int,
	visited: ^map[Coord]bool,
) -> (
	tile: Coord,
	dist: int,
) {
	// fmt.println("calculating distance for", cur_tile, cur_dist)
	if slice.contains(cross_tiles, cur_tile) do return cur_tile, cur_dist

	for t in next_tiles[cur_tile] {
		if !visited[t] {
			// fmt.println("not visited", t)
			visited[cur_tile] = true
			return calculate_distance(cross_tiles, next_tiles, t, cur_dist + 1, visited)
		}
	}

	// dead-end
	return
}

Tile_Distance :: struct {
	tile:     Coord,
	distance: int,
}

create_graph :: proc(
	cross_tiles: []Coord,
	next_tiles: map[Coord][]Coord,
) -> (
	graph: map[Coord][dynamic]Tile_Distance,
) {
	for c in cross_tiles {
		// fmt.println("graph:", c)
		for n in next_tiles[c] {
			visited := make(map[Coord]bool)
			defer delete(visited)
			visited[c] = true
			t, d := calculate_distance(cross_tiles, next_tiles, n, 1, &visited)
			// fmt.println("td:", t, d)
			if d != 0 {
				if c not_in graph do graph[c] = make([dynamic]Tile_Distance)
				td := &graph[c]
				append(td, Tile_Distance{t, d})
			}
		}
	}

	return
}

traverse :: proc(
	graph: map[Coord][dynamic]Tile_Distance,
	start, end: Coord,
	visited: ^map[Coord]bool,
	length: int,
) -> (
	distances: [dynamic]int,
) {
	if start == end {
		append(&distances, length)
	} else {
		for td in graph[start] {
			if !visited[td.tile] {
				visited[td.tile] = true
				// continue to next segment
				sub_distances := traverse(graph, td.tile, end, visited, length + td.distance)
				defer delete(sub_distances)
				for d in sub_distances {
					append(&distances, d)
				}
				delete_key(visited, td.tile)
			}
		}
	}

	return
}

