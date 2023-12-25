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

Brick :: struct {
	x, y, z:             int,
	x_len, y_len, z_len: int,
}

process_file :: proc(
	filename: string,
) -> (
	part1: int,
	part2: int,
	err: Brick_Error,
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

	bricks := parse_bricks(lines)
	defer delete(bricks)

	for b in bricks {
		fmt.println(b)
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
		brick := Brick{x, y, z, x2 - x + 1, y2 - y + 1, z2 - z + 1}
		bricks[i] = brick
	}
	return bricks
}

has_dependency :: proc(bricks: []Brick, i: int) -> (yes: int) {
	for j := i + 1; j < len(bricks); j += 1 {
		if on_top(bricks[i], bricks[j]) do return 1
	}
	return 0
}

on_top :: proc(a, b: Brick) -> bool {
	return false
}
