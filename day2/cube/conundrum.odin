package cube

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

Game_Error :: union {
	Unable_To_Read_File,
	Parse_Error,
	mem.Allocator_Error,
}

Parse_Error :: struct {}

Unable_To_Read_File :: struct {
	filename: string,
	error:    os.Errno,
}

Color :: enum {
	Red,
	Green,
	Blue,
}

Try :: struct {
	red: uint,
	green: uint,
	blue: uint,
}

Game :: struct {
	num: uint,
	tries: [dynamic]Try,
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
	red: uint = 12
	green: uint = 13 
	blue: uint = 14

	if len(arguments) != 1 && len(arguments) != 4 {
		fmt.printf("Usage: trebuchet <file> [<red> <blue> <green>]\n")
		os.exit(1)
	} else if len(arguments) == 4 {
		val: int
		ok: bool
		val, ok = strconv.parse_int(arguments[1])
		if !ok {
			fmt.printf("Error parsing red number '%s'\n", arguments[1])
			os.exit(1)
		} else {
			red = uint(val)
		}
		val, ok = strconv.parse_int(arguments[2])
		if !ok {
			fmt.printf("Error parsing green number '%d'\n", arguments[2])
			os.exit(1)
		} else {
			green = uint(val)
		}
		val, ok = strconv.parse_int(arguments[3])
		if !ok {
			fmt.printf("Error parsing blue number '%d'\n", arguments[3])
			os.exit(1)
		} else {
			blue = uint(val)
		}
	}
	filename := arguments[0]

	sum1, sum2, error := process_file(filename, red, green, blue)
	if error != nil {
		fmt.printf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.printf("answer: part1 = %d part2 = %d\n", sum1, sum2)
}

process_file :: proc(filename: string, red, green, blue: uint) -> (
	sum1, sum2: uint,
	err: Game_Error,
) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return
	}
	defer delete(data)

	it := string(data)
	for l in strings.split_lines_iterator(&it) {
		if strings.trim_space(l) == "" do continue
		sum1 += process_line_one(l, red, green, blue) or_return
		sum2 += process_line_two(l) or_return
	}

	return sum1, sum2, nil
}

process_line_one :: proc(line: string, red, green, blue: uint) -> (value: uint, err: Game_Error) {
	game := parse_line(line) or_return
	for try in game.tries {
		if try.red > red || try.green > green || try.blue > blue {
			fmt.printf("1: %d (%d %d %d) = %s\n", game.num, try.red, try.green, try.blue, line)
			return 0, nil
		}
	}
	return game.num, nil
}

process_line_two :: proc(line: string) -> (value: uint, err: Game_Error) {
	red, green, blue: uint
	game := parse_line(line) or_return
	for try in game.tries {
		if try.red > red do red = try.red
		if try.green > green do green = try.green
		if try.blue > blue do blue = try.blue
	}
	defer delete(game.tries)
	value = red * green * blue
	fmt.printf("2: %d (%d %d %d) = %s\n", value, red, green, blue, line)
	return value, nil
}

// Game 1: 1 green, 6 red, 4 blue; 2 blue, 6 green, 7 red; 3 red, 4 blue, 6 green; 3 green; 3 blue, 2 green, 1 red
parse_line :: proc(line: string) -> (game: Game, err: Game_Error) {
	pos: uint = 5
	end: uint

	game.num, end = parse_number(line, 5) 
	// fmt.printf("game: %d end: '%c'\n", game.num, line[end])
	end = end + 1 // skip _

	for end < len(line) {
		pos = end + 1 // skip _ 
		try: Try
		num: uint
		color: Color
		for line[end] != ';' && end < len(line) {
			pos = end + 1 // skip 
			num, end = parse_number(line, pos)
			// fmt.printf("num: %d end[%d]: '%c'\n", num, end, line[end])
			pos = end + 1
			color, end = parse_color(line, pos)
			// fmt.printf("color: %v end[%d]\n", color, end)
			switch color {
				case .Red: 
					try.red = num
				case .Green:
					try.green = num
				case .Blue:
					try.blue = num
			}
			if end >= len(line) || line[end] == ';' do break
			end = end + 1
		}
		append(&game.tries, try)
		if end >= len(line) do break
		end = end + 1
	}

	return game, nil
}

parse_number:: proc(line: string, pos: uint) -> (num: uint, end: uint) {
	end = pos
	for c, i in line[pos:] {
		end = pos + uint(i)
		if strings.contains_rune("0123456789", c) {
			continue
		} else {
			break
		} 
 	}
	return uint(strconv.atoi(line[pos:end])), end
}

parse_color:: proc(line: string, pos: uint) -> (Color, uint) {
	switch line[pos] {
		case 'r':  // red
			return Color.Red, pos + 3
		case 'g': // green
			return Color.Green, pos + 5
		case 'b': // blue
			return Color.Blue, pos + 4
		case:  // unreachable
 			return nil, pos
	}
}
