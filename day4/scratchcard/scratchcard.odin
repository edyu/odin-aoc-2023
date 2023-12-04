package scratchcard

import "core:fmt"
import "core:log"
import "core:math"
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
		fmt.printf("Usage: scratchcard <file>\n")
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

process_file :: proc(filename: string) -> (sum1, sum2: int, err: Game_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	for l in strings.split_lines_iterator(&it) {
		if strings.trim_space(l) == "" do continue
		sum1 += process_line_one(l) or_return
		// sum2 += process_line_two(l) or_return
	}

	return sum1, sum2, nil
}

process_line_one :: proc(line: string) -> (sum: int, err: Game_Error) {
	winners: bit_set[1 ..= 99]
	numbers: bit_set[1 ..= 99]

	colon := strings.index_rune(line, ':')
	vline := strings.index_rune(line, '|')

	winner_numbers := strings.split(line[colon + 1:vline - 1], " ")
	defer delete(winner_numbers)
	for numstr in winner_numbers {
		winners |= {strconv.atoi(numstr)}
	}

	card_numbers := strings.split(line[vline + 1:], " ")
	defer delete(card_numbers)
	for numstr in card_numbers {
		numbers |= {strconv.atoi(numstr)}
	}
	win_set := winners & numbers
	card_num_wins := card(win_set)
	if card_num_wins > 0 do sum = int(math.pow2_f16(card_num_wins - 1))
	fmt.printf("card got %d winners (%d points): %v\n", card_num_wins, sum, win_set)

	return sum, nil
}
