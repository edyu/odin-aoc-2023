package boat

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Maze_Error :: union {
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

Pipe :: struct {
	row, col: int,
	tile:     rune,
}

Direction :: enum {
	North,
	East,
	South,
	West,
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
		fmt.printf("Usage: mirage <file>\n")
		os.exit(1)
	}
	filename := arguments[0]

	time_start := time.now()
	part1, part2, error := process_file(filename)
	time_took := time.diff(time_start, time.now())
	// memory_used := arena.peak_used
	if error != nil {
		fmt.eprintf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.printf("answer: part1 = %d part2 = %d\n", part1, part2)
	fmt.printf("time took %v\n", time_took)
	// fmt.printf("memory used %v bytes\n", memory_used)
}

process_file :: proc(filename: string) -> (part1: int, part2: int, err: Maze_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	maze := find_maze(lines) or_return
	defer delete(maze)
	fmt.printf("found starting pipe at %d %d:\n", maze[0].row, maze[0].col)

	for p in maze {
		fmt.printf("%c@[%d, %d]\n", p.tile, p.row, p.col)
	}
	fmt.println("")

	part1 = len(maze) / 2

	return part1, part2, nil
}

find_maze :: proc(lines: []string) -> (maze: []Pipe, err: Maze_Error) {
	row, col: int
	for l, r in lines {
		for s, c in l {
			if s == 'S' {
				row = r
				col = c
				break
			}
		}
	}
	B: rune = 'S'
	// check top
	N := '.'
	W := '.'
	S := '.'
	E := '.'
	if row > 0 {
		N = rune(lines[row - 1][col])
	}
	if row < len(lines) - 1 {
		S = rune(lines[row + 1][col])
	}
	if col != 0 {
		W = rune(lines[row][col - 1])
	}
	if col < len(lines[row]) - 1 {
		E = rune(lines[row][col + 1])
	}
	B = find_shape(N, W, S, E)
	fmt.printf("N=%c, W=%c, S=%c, E=%c\n", N, W, S, E)

	if B == '.' {
		return maze, Parse_Error{reason = "can't figure out starting pipe"}
	} else {
		pipes := make([dynamic]Pipe)
		dir: Direction
		start := Pipe {
			tile = B,
			row  = row,
			col  = col,
		}
		append(&pipes, start)
		switch start.tile {
		case '|', 'L', 'J':
			dir = .North
			row = row - 1
		case '-', 'F':
			dir = .East
			col = col + 1
		case '7':
			dir = .South
			row = row + 1
		}
		follow_pipe(&pipes, lines, row, col, dir)

		return pipes[:], nil
	}
}

follow_pipe :: proc(maze: ^[dynamic]Pipe, lines: []string, row, col: int, dir: Direction) {
	tile := rune(lines[row][col])
	if tile == 'S' do return

	pipe := Pipe {
		tile = tile,
		row  = row,
		col  = col,
	}
	append(maze, pipe)

	switch dir {
	case .North:
		switch tile {
		case '|':
			follow_pipe(maze, lines, row - 1, col, .North)
		case '7':
			follow_pipe(maze, lines, row, col - 1, .West)
		case 'F':
			follow_pipe(maze, lines, row, col + 1, .East)
		}
	case .South:
		switch tile {
		case '|':
			follow_pipe(maze, lines, row + 1, col, .South)
		case 'J':
			follow_pipe(maze, lines, row, col - 1, .West)
		case 'L':
			follow_pipe(maze, lines, row, col + 1, .East)
		}
	case .East:
		switch tile {
		case '-':
			follow_pipe(maze, lines, row, col + 1, .East)
		case 'J':
			follow_pipe(maze, lines, row - 1, col, .North)
		case '7':
			follow_pipe(maze, lines, row + 1, col, .South)
		}
	case .West:
		switch tile {
		case '-':
			follow_pipe(maze, lines, row, col - 1, .West)
		case 'L':
			follow_pipe(maze, lines, row - 1, col, .North)
		case 'F':
			follow_pipe(maze, lines, row + 1, col, .South)
		}
	}
}

find_shape :: proc(N, W, S, E: rune) -> rune {
	if N == '|' || N == '7' || N == 'F' {
		if S == '|' || S == 'L' || S == 'J' {
			return '|'
		} else if W == '-' || W == 'L' || W == 'F' {
			return 'J'
		} else if E == '-' || E == '7' || E == 'J' {
			return 'L'
		}
	} else if S == '|' || S == 'L' || S == 'J' {
		if W == '-' || W == 'L' || W == 'F' {
			return '7'
		} else if E == '-' || E == '7' || E == 'J' {
			return 'F'
		}
	} else if W == '-' || W == 'L' || W == 'F' {
		if E == '-' || E == '7' || E == 'J' {
			return '-'
		}
	}

	return '.'
}
