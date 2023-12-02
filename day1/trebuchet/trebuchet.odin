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
	arguments := os.args[1:]

	if len(arguments) < 1 {
		fmt.printf("Usage: trebuchet <file> \n")
		os.exit(1)
	}
	filename := arguments[0]

	sum, error := process_file(filename)
	if error != nil {
		fmt.printf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.println("answer is", sum)
}

process_file :: proc(filename: string) -> (sum: int, err: Trebuchet_Error) {
	data, ok := os.read_entire_file(filename, context.allocator)
	if !ok {
		return
	}
	defer delete(data, context.allocator)

	it := string(data)
	for l in strings.split_lines_iterator(&it) {
		if strings.trim_space(l) == "" do continue
		sum += process_line(l)
	}

	return sum, nil
}

process_line :: proc(line: string) -> (value: int) {
	begin, end: rune
	got_begin: bool
	result: strings.Builder
	for c in line {
		if strings.contains_rune("0123456789", c) {
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

	fmt.printf("%s = %d\n", line, value)
	return
}
