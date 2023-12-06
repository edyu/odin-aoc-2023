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

Range_Map :: struct {
	source:      int,
	destination: int,
	length:      int,
}

Range :: struct {
	seed:   int,
	length: int,
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
	end2 := end
	defer delete(seeds)
	seeds2 := parse_seed_ranges(seeds)
	defer delete(seeds2)

	for i := end + 1; i < len(lines); {
		seeds, end = process_map(lines, i, &seeds) or_return
		i = end + 1
	}
	for s in seeds {
		if min1 == 0 || min1 > s do min1 = s
	}

	for i := end2 + 1; i < len(lines); {
		seeds2, end2 = process_range_map(lines, i, &seeds2) or_return
		i = end2 + 1
	}
	for s in seeds2 {
		if min2 == 0 || min2 > s.seed do min2 = s.seed
	}

	return min1, min2, nil
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

expand_seed_range :: proc(range: Range) -> (seeds: [dynamic]int) {
	for i := 0; i < range.length; i += 1 {
		append(&seeds, range.seed + i)
	}
	return seeds
}

parse_seed_ranges :: proc(ranges: [dynamic]int) -> (seeds: [dynamic]Range) {
	for i := 0; i < len(ranges); i += 2 {
		append(&seeds, Range{seed = ranges[i], length = ranges[i + 1]})
	}
	return seeds
}

parse_range_maps :: proc(
	lines: []string,
	idx: int,
) -> (
	maps: [dynamic]Range_Map,
	end: int,
	err: Almanac_Error,
) {
	for i := idx + 1; i < len(lines); i += 1 {
		end = i
		if lines[i] == "" do break
		map_string := strings.split(lines[i], " ")
		defer delete(map_string)
		if len(map_string) != 3 {
			return maps, end, Parse_Error{"wrong range format"}
		}
		range_map: Range_Map
		range_map.destination = strconv.atoi(map_string[0])
		range_map.source = strconv.atoi(map_string[1])
		range_map.length = strconv.atoi(map_string[2])
		append(&maps, range_map)
	}
	return maps, end, nil
}

process_map :: proc(
	lines: []string,
	idx: int,
	source: ^[dynamic]int,
) -> (
	destination: [dynamic]int,
	end: int,
	err: Almanac_Error,
) {
	log.debugf("processing %s\n", lines[idx])
	colon := strings.index_rune(lines[idx], ':')
	if colon > 0 {
		defer delete(source^)
		maps, i := parse_range_maps(lines, idx) or_return
		defer delete(maps)
		for s in source {
			found: bool
			for m in maps {
				if s >= m.source && s < m.source + m.length {
					append(&destination, m.destination + (s - m.source))
					found = true
					break
				}
			}
			if !found {
				// fmt.printf("non-range: %d\n", s)
				append(&destination, s)
			}
		}
		return destination, i, nil
	} else do return source^, idx, Parse_Error{"no map header"}
}

process_range_map :: proc(
	lines: []string,
	idx: int,
	source: ^[dynamic]Range,
) -> (
	destination: [dynamic]Range,
	end: int,
	err: Almanac_Error,
) {
	log.debugf("processing %s\n", lines[idx])
	colon := strings.index_rune(lines[idx], ':')
	if colon > 0 {
		defer delete(source^)
		maps, i := parse_range_maps(lines, idx) or_return
		defer delete(maps)
		for s in source {
			found: bool
			// fmt.printf("source: %v\n", s)
			for m in maps {
				// fmt.printf("range_map: %v\n", m)
				// out of range
				if s.seed + s.length <= m.source ||
				   s.seed >= m.source + m.length {
					// fmt.println("out of range:", s)
					continue
				}
				if s.seed >= m.source {
					if s.seed + s.length <= m.source + m.length {
						// fmt.println("completely inside range:", s, m)
						// completely inside
						inside := Range {
							seed   = m.destination + (s.seed - m.source),
							length = s.length,
						}
						append(&destination, inside)
						found = true
					} else { 	// if s.seed + s.length > m.source + m.length
						// front is inside
						// add inside range first
						// fmt.println("front inside range:", s, m)
						inside := Range {
							seed   = m.destination + (s.seed - m.source),
							length = m.length - (s.seed - m.source),
						}
						append(&destination, inside)
						outside := Range {
							seed   = s.seed + inside.length,
							length = s.length - inside.length,
						}
						append(source, outside)
						found = true
					}
				} else { 	// s.seed < m.source
					if s.seed + s.length <= m.source + m.length {
						// fmt.println("back inside range:", s, m)
						// back is inside
						// add inside range first
						inside := Range {
							seed   = m.destination,
							length = s.seed + s.length - m.source,
						}
						append(&destination, inside)
						outside := Range {
							seed   = s.seed,
							length = m.source - s.seed,
						}
						append(source, outside)
						found = true
					} else {
						// front and back are outside
						// fmt.println("middle inside range:", s, m)
						front := Range {
							seed   = s.seed,
							length = m.source - s.seed,
						}
						append(source, front)
						inside := Range {
							seed   = m.destination,
							length = m.length,
						}
						append(&destination, inside)
						back := Range {
							seed   = s.seed + front.length + m.length,
							length = s.length - front.length - m.length,
						}
						append(source, back)
						found = true
					}
				}
				if found do break
			}
			if !found {
				fmt.printf("non-range: %v\n", s)
				append(&destination, s)
			}
		}
		return destination, i, nil
	} else do return source^, idx, Parse_Error{"no map header"}
}
