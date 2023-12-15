package parabolic

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Dish_Error :: union {
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

Platform :: struct {
	mirror: [][]u8,
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

	cycles := 1_000_000_000
	if len(arguments) < 1 {
		fmt.printf("Usage: %s <file> [<cycles>]\n", os.args[0])
		os.exit(1)
	}
	filename := arguments[0]

	if len(arguments) > 1 do cycles = strconv.atoi(arguments[1])

	time_start := time.tick_now()
	part1, part2, error := process_file(filename, cycles)
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

process_file :: proc(filename: string, cycles: int) -> (part1: int, part2: int, err: Dish_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	if lines[len(lines) - 1] == "" do lines = lines[0:len(lines) - 1]

	for i in 0 ..< len(lines[0]) {
		part1 += calculate_load(lines, i)
	}
	fmt.println("part1=", part1)

	platform := parse_platform(lines)
	defer delete(platform.mirror)
	defer for r in platform.mirror do delete(r)
	// spin_cycle(platform, 1_000_000_000)
	spin_cycle(platform, cycles)

	// print_platform(platform)

	part2 = calculate_mirror_load(platform)

	return part1, part2, nil
}

print_platform :: proc(platform: Platform) {
	for i in 0 ..< len(platform.mirror) {
		for j in 0 ..< len(platform.mirror[0]) {
			fmt.printf("%c", platform.mirror[i][j])
		}
		fmt.println("")
	}
	fmt.println("")
}

spin_cycle :: proc(platform: Platform, cycle: int) {
	for c in 0 ..< cycle {
		spin_cycle_north(platform)
		spin_cycle_west(platform)
		spin_cycle_south(platform)
		spin_cycle_east(platform)
	}
}

spin_cycle_north :: proc(platform: Platform) {
	for col in 0 ..< len(platform.mirror[0]) {
		for i := 0; i < len(platform.mirror); i += 1 {
			if platform.mirror[i][col] == '.' {
				for j := i + 1; j < len(platform.mirror); j += 1 {
					if platform.mirror[j][col] == '#' {
						break
					} else if platform.mirror[j][col] == 'O' {
						platform.mirror[i][col] = 'O'
						platform.mirror[j][col] = '.'
						break
					}
				}
			}
		}
	}
}

spin_cycle_south :: proc(platform: Platform) {
	for col in 0 ..< len(platform.mirror[0]) {
		for i := len(platform.mirror) - 1; i >= 0; i -= 1 {
			if platform.mirror[i][col] == '.' {
				for j := i - 1; j >= 0; j -= 1 {
					if platform.mirror[j][col] == '#' {
						break
					} else if platform.mirror[j][col] == 'O' {
						platform.mirror[i][col] = 'O'
						platform.mirror[j][col] = '.'
						break
					}
				}
			}
		}
	}
}

spin_cycle_west :: proc(platform: Platform) {
	for row in 0 ..< len(platform.mirror) {
		for i := 0; i < len(platform.mirror[0]); i += 1 {
			if platform.mirror[row][i] == '.' {
				for j := i + 1; j < len(platform.mirror[0]); j += 1 {
					if platform.mirror[row][j] == '#' {
						break
					} else if platform.mirror[row][j] == 'O' {
						platform.mirror[row][i] = 'O'
						platform.mirror[row][j] = '.'
						break
					}
				}
			}
		}
	}
}

spin_cycle_east :: proc(platform: Platform) {
	for row in 0 ..< len(platform.mirror) {
		for i := len(platform.mirror[0]) - 1; i >= 0; i -= 1 {
			if platform.mirror[row][i] == '.' {
				for j := i - 1; j >= 0; j -= 1 {
					if platform.mirror[row][j] == '#' {
						break
					} else if platform.mirror[row][j] == 'O' {
						platform.mirror[row][i] = 'O'
						platform.mirror[row][j] = '.'
						break
					}
				}
			}
		}
	}
}

parse_platform :: proc(lines: []string) -> (platform: Platform) {
	platform.mirror = make([][]u8, len(lines))

	for i := 0; i < len(lines); i += 1 {
		line := make([]u8, len(lines[0]))
		for j := 0; j < len(lines[i]); j += 1 {
			line[j] = lines[i][j]
		}
		platform.mirror[i] = line
	}

	return platform
}

calculate_mirror_load :: proc(platform: Platform) -> (load: int) {
	for col in 0 ..< len(platform.mirror[0]) {
		col_load := 0
		for i := 0; i < len(platform.mirror); i += 1 {
			weight := len(platform.mirror) - i
			if platform.mirror[i][col] == 'O' {
				col_load += weight
			}
		}
		load += col_load
	}

	return load
}

calculate_load :: proc(lines: []string, col: int) -> (load: int) {
	next := 0
	for i := 0; i < len(lines); i += 1 {
		weight := len(lines) - next
		switch lines[i][col] {
		case '#':
			next = i + 1
		case 'O':
			load += weight
			next += 1
		case '.':
			continue
		}
	}

	return load
}

