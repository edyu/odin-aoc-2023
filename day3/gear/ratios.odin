package gear

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

Schematic_Error :: union {
	Unable_To_Read_File,
	Parse_Error,
	mem.Allocator_Error,
}

Parse_Error :: struct {}

Unable_To_Read_File :: struct {
	filename: string,
	error:    os.Errno,
}

Part :: struct {
	number:   int,
	location: Coordinate,
	length:   int,
}

Gear :: struct {
	location: Coordinate,
	parts:    [2]^Part,
}

Coordinate :: struct {
	x: int,
	y: int,
}

Schematic :: struct {
	rows:    int,
	cols:    int,
	diagram: map[Coordinate]rune,
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
		fmt.printf("Usage: gear <file>\n")
		os.exit(1)
	}
	filename := arguments[0]

	sum1, sum2, error := process_file(filename)
	if error != nil {
		fmt.eprintf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.printf("answer: part1 = %d part2 = %d\n", sum1, sum2)
}

process_file :: proc(
	filename: string,
) -> (
	sum1, sum2: int,
	err: Schematic_Error,
) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	schematic: Schematic
	defer delete(schematic.diagram)
	parts: [dynamic]Part
	defer delete(parts)
	gears: [dynamic]Gear
	defer delete(gears)
	for l in strings.split_lines_iterator(&it) {
		if strings.trim_space(l) == "" do continue
		populate_schematic(&schematic, l, &parts, &gears)
	}
	fmt.printf(
		"schematic has rows=%d cols=%d\n",
		schematic.rows,
		schematic.cols,
	)

	for part in parts {
		sum1 += check_part(&schematic, part)
	}
	for gear, i in gears {
		ratio, is_gear := check_gear(&schematic, &parts, &gears[i])
		if is_gear {
			sum2 += ratio
		}
	}
	return sum1, sum2, nil
}

populate_schematic :: proc(
	schematic: ^Schematic,
	line: string,
	parts: ^[dynamic]Part,
	gears: ^[dynamic]Gear,
) {
	if schematic.rows == 0 do schematic.cols = len(line)
	for i := 0; i < len(line); {
		schematic.diagram[Coordinate{x = schematic.rows, y = i}] = rune(
			line[i],
		)
		switch line[i] {
		case '.':
		case '0' ..= '9':
			part, skip := process_number(schematic, line, schematic.rows, i)
			i += skip
			append(parts, part)
			continue
		case '*':
			gear: Gear
			gear.location = Coordinate {
				x = schematic.rows,
				y = i,
			}
			append(gears, gear)
		case:
		}
		i += 1
	}
	schematic.rows += 1
}

process_number :: proc(
	schematic: ^Schematic,
	line: string,
	row: int,
	index: int,
) -> (
	part: Part,
	skip: int,
) {
	for i := index; i < len(line); i += 1 {
		if strings.contains_rune("0123456789", rune(line[i])) {
			skip += 1
		} else do break
	}
	if (skip > 0) {
		part.number = strconv.atoi(line[index:index + skip])
		part.location = Coordinate {
			x = row,
			y = index,
		}
		part.length = skip
	}
	return
}

check_part :: proc(schematic: ^Schematic, part: Part) -> int {
	n := part.location.x + 1
	m := part.location.y + part.length
	for i := part.location.x - 1; i <= n; i += 1 {
		for j := part.location.y - 1; j <= m; j += 1 {
			// skip the number itself
			if i == part.location.x && j >= part.location.y && j < part.location.y + part.length do continue
			if check_coordinate(schematic.rows, schematic.cols, i, j) {
				if schematic.diagram[Coordinate{x = i, y = j}] != '.' &&
				   !strings.contains_rune(
						   "0123456789",
						   schematic.diagram[Coordinate{x = i, y = j}],
					   ) {
					// log.debugf("found part number %d\n", part.number)
					return part.number
				}
			}
		}
	}
	return 0
}

check_coordinate :: proc(rows, cols, x, y: int) -> bool {
	if x >= 0 && y >= 0 && x < rows && y < cols do return true
	return false
}

is_neighbor :: proc(part: Part, gear: Gear) -> bool {
	if part.location.x >= gear.location.x - 1 &&
	   part.location.x <= gear.location.x + 1 {
		if (part.location.y >= gear.location.y - 1 &&
			   part.location.y <= gear.location.y + 1) ||
		   (part.location.y + part.length - 1 >= gear.location.y - 1 &&
				   part.location.y + part.length - 1 <= gear.location.y + 1) {
			return true
		}
	}
	return false
}

check_gear :: proc(
	schematic: ^Schematic,
	parts: ^[dynamic]Part,
	gear: ^Gear,
) -> (
	ratio: int,
	is_gear: bool,
) {
	i := 0
	for part in parts {
		if is_neighbor(part, gear^) {
			if i > 2 do break
			gear.parts[i] = &part
			i += 1
		}
	}

	if i != 2 {
		gear.parts[0] = nil
		gear.parts[1] = nil
		return 0, false
	}
	// log.debugf("found gear(x=%d, y=%d): part1=%d part2=%d\n", gear.location.x, gear.location.y, gear.parts[0].number, gear.parts[1].number)
	return gear.parts[0].number * gear.parts[1].number, true
}
