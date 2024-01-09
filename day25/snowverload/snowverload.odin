package snowverload

import q "core:container/queue"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/big"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Overload_Error :: union {
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

Graph :: map[int][dynamic]int

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

process_file :: proc(
	filename: string,
) -> (
	part1: int,
	part2: int,
	err: Overload_Error,
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

	graph, edges := parse_connections(lines)
	defer delete(graph)
	defer for e in graph do delete(graph[e])
	defer delete(edges)
	// count := count_components(graph, 0)
	// fmt.println("count:", count)
	dist := compute_distance(graph)
	defer delete(dist)
	defer for d in dist do delete(dist[d])
	// fmt.println("distance:", dist)
	part1 = cut_components(graph, edges, dist)

	return
}

parse_connections :: proc(
	lines: []string,
) -> (
	graph: Graph,
	edges: [dynamic][2]int,
) {
	node_id_map: map[string]int
	defer delete(node_id_map)
	i := 0
	for line in lines {
		values := strings.split_multi(line, []string{": ", " "})
		defer delete(values)

		if values[0] not_in node_id_map {
			node_id_map[values[0]] = i
			graph[i] = make([dynamic]int)
			i += 1
		}
		m := node_id_map[values[0]]
		for c in values[1:] {
			if c not_in node_id_map {
				node_id_map[c] = i
				graph[i] = make([dynamic]int)
				i += 1
			}
			n := node_id_map[c]
			add_edge(&graph, m, n)
			append(&edges, [2]int{m, n})
		}
	}
	// fmt.println("nodes->id")
	// fmt.println(node_id_map)
	// fmt.println("graph")
	// fmt.println(graph)

	return
}

add_edge :: proc(graph: ^Graph, a, b: int) {
	if !slice.contains(graph[a][:], b) {
		append(&graph[a], b)
	}
	if !slice.contains(graph[b][:], a) {
		append(&graph[b], a)
	}
}

remove_directed_edge :: proc(graph: ^Graph, a: int, b: int) {
	idx := -1
	for &n, i in &graph[a] {
		if n == b {
			idx = i
			break
		}
	}
	if idx != -1 do unordered_remove(&graph[a], idx)
}

del_edge :: proc(graph: ^Graph, a, b: int) {
	remove_directed_edge(graph, a, b)
	remove_directed_edge(graph, b, a)
}

count_components :: proc(graph: Graph, e: int) -> (count: int) {
	visited: map[int]bool
	defer delete(visited)

	count += visit(graph, e, &visited)

	return
}

visit :: proc(graph: Graph, e: int, visited: ^map[int]bool) -> (count: int) {
	visited[e] = true
	count += 1

	for n in graph[e] {
		if !visited[n] {
			count += visit(graph, n, visited)
		}
	}

	return
}

compute_distance :: proc(graph: Graph) -> (dist: map[int][]int) {
	for e in graph {
		dist[e] = make([]int, len(graph))
		d := dist[e]
		for i := 0; i < len(graph); i += 1 {
			d[i] = 100000
		}
	}
	for e in graph {
		work: q.Queue(int)
		defer q.destroy(&work)
		q.push(&work, e)
		d := &dist[e]
		d[e] = 0
		for q.len(work) != 0 {
			a := q.pop_front(&work)
			for b in graph[a] {
				if d[b] == 100000 {
					d[b] = d[a] + 1
					q.push(&work, b)
				}
			}
		}
	}

	return
}

maybe_bridge :: proc(graph: Graph, dist: map[int][]int, a, b: int) -> bool {
	n := len(graph) / 5
	nope := 0

	for i := 0; i < n; i += 1 {
		r := rand.int_max(len(graph))
		if math.abs(dist[a][r] - dist[b][r]) == 0 {
			nope += 1
		}
	}

	return nope <= (len(graph) / 100)
}

cut_components :: proc(
	graph: Graph,
	edges: [dynamic][2]int,
	dist: map[int][]int,
) -> (
	count: int,
) {
	graph := graph
	for i := 0; i < len(edges); i += 1 {
		e := edges[i]
		if maybe_bridge(graph, dist, e.x, e.y) {
			del_edge(&graph, e.x, e.y)
			fmt.println("cutting", e.x, e.y)

			for j := 0; j < len(edges); j += 1 {
				if j == i do continue
				d := edges[j]
				if maybe_bridge(graph, dist, d.x, d.y) {
					del_edge(&graph, d.x, d.y)
					fmt.println("cutting", d.x, d.y)

					for k := 0; k < len(edges); k += 1 {
						if k == i || k == j do continue
						g := edges[k]
						if maybe_bridge(graph, dist, g.x, g.y) {
							del_edge(&graph, g.x, g.y)
							fmt.println("cutting", g.x, g.y)

							count = count_components(graph, 0)
							fmt.println("count=", count)
							if count < len(graph) {
								return count * (len(graph) - count)
							}
							add_edge(&graph, g.x, g.y)
						}
					}
					add_edge(&graph, d.x, d.y)
				}
			}
			add_edge(&graph, e.x, e.y)
		}
	}

	fmt.println("no solution found!")
	return 0
}
