package lens

import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Hash_Error :: union {
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
		fmt.printf("Usage: %s <file>\n", os.args[0])
		os.exit(1)
	}
	filename := arguments[0]

	time_start := time.tick_now()
	part1, part2, error := process_file(filename)
	time_took := time.tick_since(time_start)
	// memory_used := arena.peak_used
	if error != nil {
		fmt.eprintf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.printf("answer: part1 = %d part2 = %d\n", part1, part2)
	fmt.printf("time took %v\n", time_took)
	// fmt.printf("memory used %v bytes\n", memory_used)
}

process_file :: proc(filename: string) -> (part1: int, part2: int, err: Hash_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	if lines[len(lines) - 1] == "" do lines = lines[0:len(lines) - 1]

	part1 += initialize(lines[0])

	part2 += initialize_lens(lines[0])

	return part1, part2, nil
}

Box :: struct {
	label:        string,
	focal_length: int,
}

initialize_lens :: proc(sequence: string) -> (power: int) {
	boxes: [256][dynamic]Box
	defer for b in boxes do delete(b)

	for i := 0; i < len(sequence); i += 1 {
		j := i + 1
		for ; j < len(sequence); j += 1 {
			if sequence[j] == '=' || sequence[j] == '-' {
				break
			}
		}
		label := sequence[i:j]
		hash := HASH(label)
		focal_length: int

		// fmt.printf("%s is in box[%d]\n", label, hash)

		remove := false

		switch sequence[j] {
		case '=':
			i = j + 1
			j = i + 1
			for ; j < len(sequence); j += 1 {
				if sequence[j] == ',' {
					break
				}
			}
			focal_length = strconv.atoi(sequence[i:j])
		// fmt.printf("box[%d][label=%s, focal_length=%d]\n", hash, label, focal_length)
		case '-':
			remove = true
			j += 1
		}

		found := -1
		for k := 0; k < len(boxes[hash]); k += 1 {
			if boxes[hash][k].label == label {
				found = k
				break
			}
		}
		if found >= 0 {
			if remove {
				// fmt.printf("removing box[%d][label=%s]\n", hash, label)
				ordered_remove(&boxes[hash], found)
			} else {
				// fmt.printf("setting box[%d][label=%s]focal_length=%d\n", hash, label, focal_length)
				boxes[hash][found].focal_length = focal_length
			}
		} else if !remove {
			// fmt.printf("adding box[%d][label=%s, focal_length=%d]\n", hash, label, focal_length)
			append(&boxes[hash], Box{label = label, focal_length = focal_length})
		}
		i = j
	}

	return calculate_power(boxes)
}

calculate_power :: proc(boxes: [256][dynamic]Box) -> (power: int) {
	for i := 0; i < 256; i += 1 {
		for j := 0; j < len(boxes[i]); j += 1 {
			power += (i + 1) * (j + 1) * boxes[i][j].focal_length
		}
	}
	return
}

initialize :: proc(sequence: string) -> (sum: int) {
	for i := 0; i < len(sequence); i += 1 {
		j := i + 1
		for ; j < len(sequence); j += 1 {
			if sequence[j] == ',' {
				break
			}
		}
		step := sequence[i:j]
		sum += HASH(step)
		i = j
	}

	return sum
}

HASH :: proc(step: string) -> (hash: int) {
	for i := 0; i < len(step); i += 1 {
		hash += int(step[i])
		hash *= 17
		hash %= 256
	}
	return hash
}

