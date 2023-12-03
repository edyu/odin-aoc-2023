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
	number: int,
	location: Coordinate,
	length: int,
}

Coordinate :: struct {
	x: int,
	y: int,
}

Schematic :: struct {
	rows: int,
	cols: int,
	diagram: map[Coordinate]rune,
}

main :: proc() {
	context.logger = log.create_console_logger()
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
		fmt.printf("Usage: gear <file>\n")
		os.exit(1)
	}
	filename := arguments[0]

	sum1, sum2, error := process_file(filename)
	if error != nil {
		fmt.printf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.printf("answer: part1 = %d part2 = %d\n", sum1, sum2)
}

process_file :: proc(filename: string) -> (
	sum1, sum2: int,
	err: Schematic_Error,
) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{ filename = filename }
	}
	defer delete(data)

	it := string(data)
	schematic : Schematic
	defer delete(schematic.diagram)
	engine : [dynamic]Part
	defer delete(engine)
	for l in strings.split_lines_iterator(&it) {
		if strings.trim_space(l) == "" do continue
		populate_schematic(&schematic, l, &engine)
	}
	fmt.printf("schematic has rows=%d cols=%d\n", schematic.rows, schematic.cols)

	for part in engine {
		sum1 += check_part(&schematic, part)
	}
	return sum1, 0, nil
}

populate_schematic :: proc(schematic: ^Schematic, line: string, engine: ^[dynamic]Part) {
	fmt.printf("processing line %d\n", schematic.rows)
	if schematic.rows == 0 do schematic.cols = len(line)
	for i := 0; i < len(line); {
		schematic.diagram[Coordinate{ x = schematic.rows, y = i }] = rune(line[i])
		switch line[i] {
			case '.':
			case '0'..='9': 
				part, skip := process_number(schematic, line, schematic.rows, i)
				fmt.printf("found number=%d\n", part.number)
				i += skip
				append(engine, part)
				continue
			case:
				fmt.printf("found symbol=%c\n", line[i])
		}
		i += 1
	}
	schematic.rows += 1
}

process_number :: proc(schematic: ^Schematic, line: string, row: int, index: int) -> (part: Part, skip: int) {
	for i := index; i < len(line); i += 1 {
		if strings.contains_rune("0123456789", rune(line[i])) {
			skip += 1
		} else do break
	}
	if (skip > 0) {
		part.number = strconv.atoi(line[index:index + skip])
		part.location = Coordinate{ x = row, y = index }
		part.length = skip
	}
	return
}

check_part :: proc(schematic: ^Schematic, part: Part) -> int {
	n := part.location.x + 1
	m := part.location.y + part.length + 1
	for i := part.location.x - 1; i <= n; i += 1 {
		for j := part.location.y - 1; j <= m; j += 1 {
			// skip the number itself
			if i == part.location.x && j >= part.location.y && j < part.location.y + part.length do continue 
			if check_coordinate(schematic.rows, schematic.cols, i, j) {
				if schematic.diagram[Coordinate{ x = i, y = j}] != '.' &&
					!strings.contains_rune("0123456789", schematic.diagram[Coordinate{ x = i, y = j}]) {
					fmt.printf("found part number %d\n", part.number)
					return part.number
				}
			}	
		}
	}
	return 0
}

check_coordinate :: proc(rows, cols, x, y : int) -> bool {
	if x >= 0 && y >= 0 && x < rows && y < cols do return true
	return false
}

