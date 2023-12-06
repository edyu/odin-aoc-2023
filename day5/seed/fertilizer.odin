package seed

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

Almanac_Error :: union {
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

Range :: struct {
	source:      int,
	destination: int,
	length:      int,
}

Entry :: struct {
	seed:        int,
	soil:        int,
	fertilizer:  int,
	water:       int,
	light:       int,
	temperature: int,
	humidity:    int,
	location:    int,
}

main :: proc() {
	context.logger = log.create_console_logger()
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
		fmt.printf("Usage: seed <file>\n")
		os.exit(1)
	}
	filename := arguments[0]

	min1, min2, error := process_file(filename)
	if error != nil {
		fmt.eprintf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.printf("answer: part1 = %d part2 = %d\n", min1, min2)
}

process_file :: proc(
	filename: string,
) -> (
	min1: int,
	min2: int,
	err: Almanac_Error,
) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	seeds, end := get_seeds(lines) or_return
	defer delete(seeds)
	for i := end + 1; i < len(lines); {
		seeds, end = process_map(lines, i, seeds) or_return
		fmt.printf("end=%d len(seeds)=%d\n", end, len(seeds))
		i = end + 1
	}

	for s in seeds {
		fmt.printf("locaton: %d\n", s)
		if min1 == 0 || min1 > s do min1 = s
	}

	return min1, 0, nil
}

get_seeds :: proc(
	lines: []string,
) -> (
	seeds: [dynamic]int,
	end: int,
	err: Almanac_Error,
) {
	line := lines[0]
	// seeds: 
	if line[0:7] == "seeds: " {
		seed_strings := strings.split(line[7:], " ")
		defer delete(seed_strings)
		for s in seed_strings {
			append(&seeds, strconv.atoi(s))
		}
	} else do return seeds, 0, Parse_Error{reason = "wrong almanac format"}
	return seeds, 1, nil
}

process_map :: proc(
	lines: []string,
	idx: int,
	source: [dynamic]int,
) -> (
	destination: [dynamic]int,
	end: int,
	err: Almanac_Error,
) {
	colon := strings.index_rune(lines[idx], ':')
	if colon > 0 {
		defer delete(source)
		i: int
		ranges: [dynamic]Range
		defer delete(ranges)
		for i = idx + 1; i < len(lines); i += 1 {
			if lines[i] == "" do break
			range_string := strings.split(lines[i], " ")
			defer delete(range_string)
			if len(range_string) != 3 {
				return destination, i, Parse_Error{"wrong range format"}
			}
			range: Range
			range.destination = strconv.atoi(range_string[0])
			range.source = strconv.atoi(range_string[1])
			range.length = strconv.atoi(range_string[2])
			append(&ranges, range)

			fmt.printf("range: %v\n", range)
		}
		for s in source {
			found: bool
			for r in ranges {
				if s >= r.source && s < r.source + r.length {
					append(&destination, r.destination + (s - r.source))
					found = true
					break
				}
			}
			if !found do append(&destination, s)
		}
		return destination, i, nil
	} else do return source, idx, Parse_Error{"no map header"}
}
