package sand

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

Brick_Error :: union {
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

Brick :: struct {
	order: int,
	coord: [3]int,
	len:   [3]int,
}

process_file :: proc(filename: string) -> (part1: int, part2: int, err: Brick_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	if lines[len(lines) - 1] == "" do lines = lines[0:len(lines) - 1]

	bricks := parse_bricks(lines)
	defer delete(bricks)

	slice.sort_by(bricks, proc(a, b: Brick) -> bool {return a.coord.z < b.coord.z})

	// fmt.println("after sort")
	// for i := 0; i < len(bricks); i += 1 {
	// 	fmt.printf("%c: %v\n", bricks[i].order + 'A', bricks[i])
	// }

	supports: map[int][dynamic]int
	defer delete(supports)
	defer for _, v in supports do delete(v)
	for i := 0; i < len(bricks); i += 1 {
		deps := let_it_fall(bricks, i)
		// fmt.printf("%c found deps: %v\n", bricks[i].order + 'A', deps)
		defer delete(deps)
		for d in deps {
			if !(d in supports) do supports[d] = make([dynamic]int)
			existing := &supports[d]
			if !slice.contains(existing[:], bricks[i].order) {
				append(existing, bricks[i].order)
			}
		}
	}

	// fmt.println("after falling down")

	slice.sort_by(bricks, proc(a, b: Brick) -> bool {return a.coord.z < b.coord.z})

	// for i := 0; i < len(bricks); i += 1 {
	// 	fmt.printf("%c: %v\n", bricks[i].order + 'A', bricks[i])
	// }

	for k, v in supports {
		slice.sort(supports[k][:])
		fmt.printf("supports[%c]=", k + 'A')
		if len(v) == 0 do fmt.printf("[]\n")
		else {
			fmt.printf("[ ")
			for n in v {
				fmt.printf("%c ", n + 'A')
			}
			fmt.printf("]\n")
		}
	}

	outer: for k, v in supports {
		if len(v) > 0 {
			// fmt.printf("checking %c\n", k + 'A')
			middle: for i in v {
				// fmt.printf("trying to find %c\n", i + 'A')
				found := false
				inner: for j, u in supports {
					// fmt.printf("against %v\n", u)
					if j != k {
						if slice.contains(u[:], i) {
							// fmt.printf("found at %c\n", j + 'A')
							found = true
							break inner
						}
					}
				}
				if !found {
					// fmt.printf("%c not found\n", i + 'A')
					continue outer
				}
			}
			// fmt.printf("%c is not the only support\n", k + 'A')
			part1 += 1
		}
	}

	for i := 0; i < len(bricks); i += 1 {
		if !(i in supports) {
			// fmt.printf("%c doesn't support anything\n", i + 'A')
			part1 += 1
		}
	}

	return
}

parse_bricks :: proc(lines: []string) -> (bricks: []Brick) {
	bricks = make([]Brick, len(lines))
	for l, i in lines {
		values := strings.split_multi(l, {"~", ","})
		defer delete(values)
		assert(len(values) == 6)
		x := strconv.atoi(values[0])
		y := strconv.atoi(values[1])
		z := strconv.atoi(values[2])
		x2 := strconv.atoi(values[3])
		y2 := strconv.atoi(values[4])
		z2 := strconv.atoi(values[5])
		brick := Brick{i, {x, y, z}, {x2 - x + 1, y2 - y + 1, z2 - z + 1}}
		bricks[i] = brick
	}
	return bricks
}

let_it_fall :: proc(bricks: []Brick, i: int) -> (deps: [dynamic]int) {
	if i == 0 && bricks[0].coord.z == 1 do return
	bricks[i].coord.z = 1
	// if bricks[i].order == 18 do fmt.printf("processing %c\n", bricks[i].order + 'A')
	for j := i - 1; j >= 0; j -= 1 {
		// if bricks[i].order == 18 do fmt.printf("checking against %c\n", bricks[j].order + 'A')
		if on_top(bricks[i], bricks[j]) {
			// if bricks[i].order == 18 do fmt.printf("on top of %c\n", bricks[j].order + 'A')
			// if bricks[i].order == 18 do fmt.printf("%v\n", bricks[j])
			bricks[i].coord.z = bricks[j].coord.z + bricks[j].len.z
			// if bricks[i].order == 18 do fmt.printf("z is %d\n", bricks[i].coord.z)
			append(&deps, bricks[j].order)
			for k := j - 1; k >= 0; k -= 1 {
				if on_top(bricks[i], bricks[k]) {
					// if bricks[i].order == 18 do fmt.printf("also on top of %v\n", bricks[k])
					if bricks[k].coord.z + bricks[k].len.z == bricks[i].coord.z {
						append(&deps, bricks[k].order)
					} else if bricks[k].coord.z + bricks[k].len.z > bricks[i].coord.z {
						// update to higher z
						bricks[i].coord.z = bricks[k].coord.z + bricks[k].len.z
						// need to remove wrongly added earlier bricks
						for d := 0; d < len(deps); d += 1 {
							if bricks[d].coord.z + bricks[d].len.z < bricks[i].coord.z {
								unordered_remove(&deps, d)
							}
						}
						append(&deps, bricks[k].order)
					}
				}
			}
			return
		}
	}

	return
}

on_top :: proc(a, b: Brick) -> bool {
	a_coords := expand_coord(a)
	defer delete(a_coords)
	b_coords := expand_coord(b)
	defer delete(b_coords)
	for i := 0; i < len(a_coords); i += 1 {
		for j := 0; j < len(b_coords); j += 1 {
			if a_coords[i] == b_coords[j] do return true
		}
	}
	return false
}

expand_coord :: proc(brick: Brick) -> (coords: [dynamic][2]int) {
	for x := brick.coord.x; x < brick.coord.x + brick.len.x; x += 1 {
		for y := brick.coord.y; y < brick.coord.y + brick.len.y; y += 1 {
			append(&coords, [2]int{x, y})
		}
	}

	return coords
}

