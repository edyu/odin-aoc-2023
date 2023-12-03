package trebuchet

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

Trebuchet_Error :: union {
	Unable_To_Read_File,
	mem.Allocator_Error,
}

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
		fmt.printf("Usage: trebuchet <file> \n")
		os.exit(1)
	}
	filename := arguments[0]

	sum1, sum2, error := process_file(filename)
	if error != nil {
		fmt.printf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.printf("answer: part 1 = %d, part 2 = %d", sum1, sum2)
}

process_file :: proc(
	filename: string,
) -> (
	sum1, sum2: int,
	err: Trebuchet_Error,
) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return
	}
	defer delete(data)

	it := string(data)
	for l in strings.split_lines_iterator(&it) {
		if strings.trim_space(l) == "" do continue
		// part 1
		sum1 += process_line_one(l)
		// part 2
		sum2 += process_line_two(l)
	}

	return sum1, sum2, nil
}

process_line_two :: proc(line: string) -> (value: int) {
	begin, end: rune
	got_begin: bool
	result: strings.Builder
	for c, i in line {
		if strings.contains_rune("0123456789", c) {
			if !got_begin {
				got_begin = true
				begin = c
				end = c
			} else {
				end = c
			}
		} else {
			// 3: one, two, six
			// 4: four, five, nine
			// 5: three, seven, eight
			new_c: rune
			if strings.has_prefix(line[i:], "one") {
				new_c = '1'
			} else if strings.has_prefix(line[i:], "two") {
				new_c = '2'
			} else if strings.has_prefix(line[i:], "three") {
				new_c = '3'
			} else if strings.has_prefix(line[i:], "four") {
				new_c = '4'
			} else if strings.has_prefix(line[i:], "five") {
				new_c = '5'
			} else if strings.has_prefix(line[i:], "six") {
				new_c = '6'
			} else if strings.has_prefix(line[i:], "seven") {
				new_c = '7'
			} else if strings.has_prefix(line[i:], "eight") {
				new_c = '8'
			} else if strings.has_prefix(line[i:], "nine") {
				new_c = '9'
			} else {
				continue
			}
			if !got_begin {
				got_begin = true
				begin = new_c
				end = new_c
			} else {
				end = new_c
			}
		}
	}
	fmt.sbprintf(&result, "%c%c", begin, end)

	value = strconv.atoi(strings.to_string(result))
	fmt.printf("2: %s = %d\n", line, value)
	return
}

process_line_one :: proc(line: string) -> (value: int) {
	begin, end: rune
	got_begin: bool
	result: strings.Builder
	for c in line {
		if strings.contains_rune("123456789", c) {
			if !got_begin {
				got_begin = true
				begin = c
				end = c
			} else {
				end = c
			}
		}
	}
	fmt.sbprintf(&result, "%c%c", begin, end)

	value = strconv.atoi(strings.to_string(result))
	fmt.printf("1: %s = %d\n", line, value)
	return
}
