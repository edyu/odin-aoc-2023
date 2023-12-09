package boat

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

Network_Error :: union {
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

Step :: enum {
	L,
	R,
}

Choice :: struct {
	left:  string,
	right: string,
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
		fmt.printf("Usage: haunted <file>\n")
		os.exit(1)
	}
	filename := arguments[0]

	step1, step2, error := process_file(filename)
	if error != nil {
		fmt.eprintf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.printf("answer: part1 = %d part2 = %d\n", step1, step2)
}

process_file :: proc(
	filename: string,
) -> (
	step1: int,
	step2: int,
	err: Network_Error,
) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)

	instructions: []Step = parse_instructions(lines[0])
	defer delete(instructions)
	network: map[string]Choice = parse_network(lines[2:])
	defer delete(network)

	step := "AAA"
	if step in network {
		step1 = find_path(network, instructions, step, part1_done)
	}

	steps := get_starting_steps(network)
	cur_step: int
	fmt.println("found total of", len(steps), "starting steps:", steps)
	defer delete(steps)
	for j in 0 ..< len(steps) {
		cur_step = find_path(network, instructions, steps[j], part2_done)

		fmt.printf("path[%d] took %d steps\n", j, cur_step)
		if j == 0 do step2 = cur_step
		else do step2 = find_lcm(step2, cur_step)
		fmt.printf("current lcm is %d\n", step2)
	}

	return step1, step2, nil
}

part1_done :: proc(step: string) -> bool {
	return step == "ZZZ"
}

part2_done :: proc(step: string) -> bool {
	return step[2] == 'Z'
}

get_starting_steps :: proc(
	network: map[string]Choice,
) -> (
	steps: [dynamic]string,
) {
	for s in network {
		if s[2] == 'A' {
			append(&steps, s)
		}
	}
	return
}

find_path :: proc(
	network: map[string]Choice,
	instructions: []Step,
	step: string,
	is_done: proc(_: string) -> bool,
) -> (
	step1: int,
) {
	step := step
	done: bool
	for !done {
		for i in 0 ..< len(instructions) {
			// fmt.println("checking", step)
			if is_done(step) {
				done = true
				break
			}
			choice := network[step]
			// fmt.println("found ", choice)
			if instructions[i] == .L do step = choice.left
			else do step = choice.right
			step1 += 1
		}
	}
	return step1
}

parse_instructions :: proc(line: string) -> (steps: []Step) {
	steps = make([]Step, len(line))
	for s, i in line {
		if s == 'L' do steps[i] = .L
		else do steps[i] = .R
	}
	return steps
}

parse_network :: proc(lines: []string) -> (network: map[string]Choice) {
	// network = make(map[string]Choice, len(lines))
	for line in lines {
		if line == "" do break
		network[line[0:3]] = Choice {
			left  = line[7:10],
			right = line[12:15],
		}
	}
	return network
}

find_lcm :: proc(a, b: int) -> int {
	return a * b / find_gcd(a, b)
}

find_gcd :: proc(a, b: int) -> int {
	a, b := a, b
	r: int
	for b != 0 {
		r = a % b
		a, b = b, r
	}
	return a
}
