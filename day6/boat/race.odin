package boat

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

Race_Error :: union {
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

Record :: struct {
	time:     int,
	distance: int,
}

Strategy :: struct {
	record: Record,
	wait:   int,
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
		fmt.printf("Usage: boat <file>\n")
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
	ways1: int,
	ways2: int,
	err: Race_Error,
) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	records, record := get_records(lines) or_return
	defer delete(records)

	ways1 = 1
	for r, i in records {
		fmt.printf("record[%d]=%v\n", i, r)
		ways1 *= find_winning_strategies(r)
	}
	fmt.printf("record=%v\n", record)
	ways2 = find_winning_strategies(record)

	return ways1, ways2, nil
}

get_records :: proc(
	lines: []string,
) -> (
	records: [dynamic]Record,
	record: Record,
	err: Race_Error,
) {
	if lines[0][0:6] == "Time: " && lines[1][0:10] == "Distance: " {
		time_line := strings.trim_left_space(lines[0][7:])
		distance_line := strings.trim_left_space(lines[1][10:])
		time_strings := strings.split(time_line, " ")
		defer delete(time_strings)
		distance_strings := strings.split(distance_line, " ")
		defer delete(distance_strings)
		i := 0
		j := 0
		time_sb, distance_sb: [dynamic]string
		defer delete(time_sb)
		defer delete(distance_sb)
		for i < len(time_strings) && j < len(distance_strings) {
			for strings.trim_space(time_strings[i]) == "" do i += 1
			for strings.trim_space(distance_strings[j]) == "" do j += 1
			append(&time_sb, time_strings[i])
			append(&distance_sb, distance_strings[j])
			append(
				&records,
				Record {
					time = strconv.atoi(time_strings[i]),
					distance = strconv.atoi(distance_strings[j]),
				},
			)
			i += 1
			j += 1
		}
		time_str := strings.join(time_sb[:], "")
		defer delete(time_str)
		distance_str := strings.join(distance_sb[:], "")
		defer delete(distance_str)
		record.time = strconv.atoi(time_str)
		record.distance = strconv.atoi(distance_str)
		return records, record, nil
	}
	return records, record, Parse_Error{reason = "wrong race record format"}
}

find_winning_strategies :: proc(record: Record) -> (ways: int) {
	for i := 1; i < record.time; i += 1 {
		if i * (record.time - i) > record.distance {
			// fmt.printf(
			// 	"%d * %d = %d > %d\n",
			// 	i,
			// 	record.time - i,
			// 	i * (record.time - i),
			// 	record.distance,
			// )
			ways += 1
		}
	}
	return
}
