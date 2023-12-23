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
		fmt.printf("Usage: %s <file> [<times>]\n", os.args[0])
		os.exit(1)
	}
	filename := arguments[0]
	times := 1000
	if len(arguments) > 1 do times = strconv.atoi(arguments[1])

	time_start := time.tick_now()
	part1, part2, error := process_file(filename, times)
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
	Button,
	Broadcast,
	Flip_Flop,
	Conjunction,
}

Button :: struct {
	name:        string,
	destination: string,
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
	inputs:       map[string]bool,
	destinations: []string,
}

process_file :: proc(
	filename: string,
	times: int = 1000,
) -> (
	part1: int,
	part2: int,
	err: Module_Error,
) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	if lines[len(lines) - 1] == "" do lines = lines[0:len(lines) - 1]

	modules := parse_configuration(&lines)
	defer delete(modules)
	defer for k in modules {
		#partial switch t in modules[k] {
		case Broadcast:
			delete(t.destinations)
		case Flip_Flop:
			delete(t.destinations)
		case Conjunction:
			delete(t.inputs)
			delete(t.destinations)
		}
	}
	for k in modules {
		fmt.println(modules[k])
	}
	low, high := press_button(modules, times)
	fmt.println("low:", low, "high:", high)
	part1 = low * high

	return part1, part2, nil
}

parse_configuration :: proc(lines: ^[]string) -> (modules: map[string]Module) {
	conjunctions: map[string]Conjunction
	defer delete(conjunctions)
	for line in lines {
		arrow := strings.index(line, " -> ")
		name := line[1:arrow]
		dst_string := line[arrow + 4:]
		if line[0] == '&' do conjunctions[name] = Conjunction {
			name         = name,
			inputs       = make(map[string]bool),
			destinations = strings.split(dst_string, ", "),
		}
	}
	fmt.println("found", len(conjunctions), "conjunctions:", conjunctions)
	for line in lines {
		arrow := strings.index(line, " -> ")
		if line[0] == '%' {
			flip_flop: Flip_Flop
			flip_flop.name = line[1:arrow]
			dst_string := line[arrow + 4:]
			flip_flop.destinations = strings.split(dst_string, ", ")
			for d in flip_flop.destinations {
				if d in conjunctions {
					c := &conjunctions[d]
					if !(flip_flop.name in c.inputs) {
						fmt.println(
							"conjunction flipflop: adding",
							flip_flop.name,
						)
						c.inputs[flip_flop.name] = false
					}
					// conjunctions[d] = c
				}
			}
			modules[flip_flop.name] = flip_flop
		} else if line[0] == '&' {
			name := line[1:arrow]
			conj := &conjunctions[name]
			for d in conj.destinations {
				if d in conjunctions {
					c := &conjunctions[d]
					if !(name in c.inputs) {
						fmt.println("conjunction conjunction: adding:", name)
						c.inputs[name] = false
					}
					// conjunctions[d] = c
				}
			}
			modules[name] = conj^
		} else {
			broadcast: Broadcast
			broadcast.name = line[0:arrow]
			dst_string := line[arrow + 4:]
			broadcast.destinations = strings.split(dst_string, ", ")
			modules[broadcast.name] = broadcast
		}
	}

	return
}

Input :: struct {
	from:  string,
	pulse: bool,
	to:    string,
}

print_signal :: proc(input: Input) {
	pulse := "-high->" if input.pulse else "-low->"
	fmt.printf("%s %s %s\n", input.from, pulse, input.to)
}

press_button :: proc(
	modules: map[string]Module,
	times: int,
) -> (
	low, high: int,
) {
	sequence: q.Queue(Input)
	defer q.destroy(&sequence)

	// initial button pulse
	for i := 0; i < times; i += 1 {
		q.push(
			&sequence,
			Input{from = "button", pulse = false, to = "broadcaster"},
		)
		for q.len(sequence) != 0 {
			input := q.pop_front(&sequence)
			// print_signal(input)
			if input.pulse do high += 1
			else do low += 1
			if input.to in modules {
				#partial switch &to in &modules[input.to] {
				case Broadcast:
					for d in to.destinations {
						q.push_back(
							&sequence,
							Input{from = to.name, pulse = input.pulse, to = d},
						)
					}
				case Conjunction:
					to.inputs[input.from] = input.pulse
					all_inputs := true
					for n in to.inputs {
						if !to.inputs[n] {
							all_inputs = false
							break
						}
					}
					if all_inputs && input.pulse { 	// remembers high pulses
						for d in to.destinations {
							// send low pulse
							q.push_back(
								&sequence,
								Input{from = to.name, pulse = false, to = d},
							)
						}
					} else { 	// remembers low pulses
						for d in to.destinations {
							// send high pulse
							q.push_back(
								&sequence,
								Input{from = to.name, pulse = true, to = d},
							)
						}
					}
				case Flip_Flop:
					if input.pulse { 	// high pulse
						// do nothing
					} else { 	// low pulse
						to.on = !to.on
						if to.on { 	// was off
							for d in to.destinations {
								// high pulse
								q.push_back(
									&sequence,
									Input {
										from = to.name,
										pulse = true,
										to = d,
									},
								)
							}
						} else { 	// was on
							for d in to.destinations {
								// low pulse
								q.push_back(
									&sequence,
									Input {
										from = to.name,
										pulse = false,
										to = d,
									},
								)
							}
						}
					}
				}
			}
		}
		// fmt.println("low:", low, "high:", high)
	}
	return
}
