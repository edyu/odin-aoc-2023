package cosmic

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Universe_Error :: union {
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

Galaxy :: struct {
	row, col: int,
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
		fmt.printf("Usage: %s <file> [<expansion>]\n", os.args[0])
		os.exit(1)
	}
	filename := arguments[0]
	expansion := 1000000
	if len(arguments) > 1 do expansion = strconv.atoi(arguments[1])

	time_start := time.tick_now()
	part1, part2, error := process_file(filename, expansion)
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
	expansion: int,
) -> (
	part1: int,
	part2: int,
	err: Universe_Error,
) {
	fmt.println("expansion is", expansion)
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	galaxies := parse_universe(lines) or_return
	defer delete(galaxies)
	galaxies2 := parse_universe(lines, expansion) or_return
	defer delete(galaxies2)
	assert(len(galaxies) == len(galaxies2))

	range := make([]int, len(galaxies))
	defer delete(range)
	for i in 0 ..< len(galaxies) do range[i] = i

	matches := choose(range, 2)
	defer delete(matches)
	defer for m in matches {
		delete(m)
	}
	fmt.println("found", len(matches), "matches")

	for m in matches {
		part1 += calculate_distance(galaxies[m[0]], galaxies[m[1]])
		part2 += calculate_distance(galaxies2[m[0]], galaxies2[m[1]])
	}

	return part1, part2, nil
}

calculate_distance :: proc(a, b: Galaxy) -> int {
	return max(a.row, b.row) - min(a.row, b.row) + max(a.col, b.col) - min(a.col, b.col)
}

parse_universe :: proc(lines: []string, e: int = 2) -> (galaxies: []Galaxy, err: Universe_Error) {
	g: [dynamic]Galaxy
	r := 0
	for i in 0 ..< len(lines) {
		if lines[i] == "" do break
		h_found := false
		c := 0
		for j in 0 ..< len(lines[0]) {
			if lines[i][j] != '.' {
				h_found = true
				append(&g, Galaxy{row = r, col = c})
			}
			v_found := false
			for k in 0 ..< len(lines) {
				if lines[k] == "" do break
				if lines[k][j] != '.' {
					v_found = true
					break
				}
			}
			if !v_found {
				c += e
			} else {
				c += 1
			}
		}
		if !h_found {
			r += e
		} else {
			r += 1
		}
	}

	return g[:], nil
}

choose :: proc(l: []int, k: int) -> (ret: [dynamic][dynamic]int) {
	assert(len(l) >= k)
	assert(k > 0)

	if (k == 1) {
		for i := 0; i < len(l); i += 1 {
			item: [dynamic]int = {l[i]}
			append(&ret, item)
		}
		return ret
	}

	c := choose(l[1:], k - 1)
	defer delete(c)
	defer for i in c do delete(i)

	for m in 0 ..< (len(l) - 1) {
		for n in 0 ..< len(c) {
			if (l[m] >= c[n][0]) do continue
			sub: [dynamic]int
			append(&sub, l[m])
			for j in 0 ..< len(c[n]) {
				append(&sub, c[n][j])
			}
			append(&ret, sub)
		}
	}
	return ret
}

