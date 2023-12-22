package pulse

import q "core:container/queue"
import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Module_Error :: union {
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

Module :: union {
	Broadcast,
	Flip_Flop,
	Conjunction,
}

Broadcast :: struct {
	name:         string,
	destinations: []string,
}

Flip_Flop :: struct {
	name:         string,
	destinations: []string,
	on:           bool,
}

Conjunction :: struct {
	name:         string,
	destinations: []string,
	remember:     bool,
}

process_file :: proc(filename: string) -> (part1: int, part2: int, err: Module_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	if lines[len(lines) - 1] == "" do lines = lines[0:len(lines) - 1]

	modules := parse_configuration(lines)
	defer delete(modules)
	defer for m in modules {
		#partial switch t in m {
		case Broadcast:
			delete(t.destinations)
		case Flip_Flop:
			delete(t.destinations)
		case Conjunction:
			delete(t.destinations)
		}
	}
	for m in modules {
		fmt.println(m)
	}
	low, high := press_button(modules[:])
	fmt.println("low:", low, "high:", high)
	part1 = low * 1000 * high * 1000

	return part1, part2, nil
}

parse_configuration :: proc(lines: []string) -> (modules: [dynamic]Module) {
	for line in lines {
		arrow := strings.index(line, " -> ")
		if line[0] == '%' {
			flip_flop: Flip_Flop
			flip_flop.name = line[1:arrow]
			dst_string := line[arrow + 4:]
			flip_flop.destinations = strings.split(dst_string, ", ")
			append(&modules, flip_flop)
		} else if line[0] == '&' {
			conjunction: Conjunction
			conjunction.name = line[1:arrow]
			dst_string := line[arrow + 4:]
			conjunction.destinations = strings.split(dst_string, ", ")
			append(&modules, conjunction)
		} else {
			broadcast: Broadcast
			broadcast.name = line[0:arrow]
			dst_string := line[arrow + 4:]
			broadcast.destinations = strings.split(dst_string, ", ")
			append(&modules, broadcast)
		}
	}

	return
}

Input :: struct {
	pulse:  bool,
	module: string,
}

press_button :: proc(modules: []Module) -> (low, high: int) {
	module_map: map[string]Module
	defer delete(module_map)
	sequence: q.Queue(Input)
	defer q.destroy(&sequence)
	for m in modules {
		switch t in m {
		case Broadcast:
			q.push_back(&sequence, Input{module = t.name})
			module_map[t.name] = m
		case Conjunction:
			q.push_back(&sequence, Input{module = t.name})
			module_map[t.name] = m
		case Flip_Flop:
			q.push_back(&sequence, Input{module = t.name})
			module_map[t.name] = m
		}
	}

	// initial button pulse
	low += 1
	fmt.println("initial(", q.len(sequence), "):", sequence)
	for q.len(sequence) != 0 {
		fmt.println("sequence.len", q.len(sequence))
		input := q.pop_front(&sequence)
		fmt.println("processing", input)
		module := module_map[input.module]
		pulse := input.pulse
		switch &m in &module_map[input.module] {
		case Broadcast:
			fmt.println("broadcast.destinations:", m.destinations)
			#reverse for d in m.destinations {
				fmt.println("adding", d, "pulse", pulse)
				q.push_front(&sequence, Input{pulse, d})
				if pulse do high += 1
				else do low += 1
			}
			fmt.println("post broadcast low:", low, "high:", high)
			fmt.println("post broadcast: sequence:", sequence)
		case Conjunction:
			if m.remember && pulse {
				pulse = false // low pulse
			} else {
				pulse = true // high pulse
			}
			m.remember = pulse
			#reverse for d in m.destinations {
				q.push_front(&sequence, Input{pulse, d})
				if pulse do high += 1
				else do low += 1
			}
		case Flip_Flop:
			if pulse { 	// high pulse
				// do nothing
			} else { 	// low pulse
				fmt.println("flipflop", m.name, "was", m.on)
				m.on = !m.on
				if m.on { 	// was off
					// q.push_front(&sequence, Input{true, m.destination})
					high += 1
				} else { 	// was on
					// q.push_front(&sequence, Input{false, m.destination})
					low += 1
				}
				fmt.println("flipflop", module_map[m.name])
				fmt.println("post flipflop low:", low, "high:", high)
			}
		}
		fmt.println(sequence)
		fmt.println("end of loop:", sequence)
	}
	return
}

