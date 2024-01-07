package odds

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

Snow_Making_Error :: union {
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

Hailstone :: struct {
	position: [3]f64,
	velocity: [3]f64,
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
		fmt.printf("Usage: %s <file> <min> <max>\n", os.args[0])
		os.exit(1)
	}
	filename := arguments[0]
	min := 200000000000000
	max := 400000000000000
	if len(arguments) >= 3 {
		min = strconv.atoi(arguments[1])
		max = strconv.atoi(arguments[2])
	}

	time_start := time.tick_now()
	fmt.println("checking between", min, "and", max)
	part1, part2, error := process_file(filename, min, max)
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

process_file :: proc(
	filename: string,
	min, max: int,
) -> (
	part1: int,
	part2: int,
	err: Snow_Making_Error,
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

	hailstones := parse_hailstones(lines)
	defer delete(hailstones)

	for i := 0; i < len(hailstones); i += 1 {
		a := hailstones[i]
		for j := i + 1; j < len(hailstones); j += 1 {
			b := hailstones[j]
			if intersects(a, b, min, max) {
				part1 += 1
			} else {
				// fmt.println(a, "doesn't intersect", b)
			}
		}
	}

	thrown, solved := position_stone(hailstones)
	if solved {
		part2 =
			int(thrown.position.x) +
			int(thrown.position.y) +
			int(thrown.position.z)
	} else {
		fmt.println("no solution; choose another set of stones")
	}
	return
}

parse_hailstones :: proc(lines: []string) -> []Hailstone {
	hailstones := make([]Hailstone, len(lines))

	for line, i in lines {
		values := strings.split_multi(line, []string{",", "@"})
		defer delete(values)
		assert(len(values) == 6)
		hailstones[i] =  {
			 {
				strconv.atof(strings.trim_space(values[0])),
				strconv.atof(strings.trim_space(values[1])),
				strconv.atof(strings.trim_space(values[2])),
			},
			 {
				strconv.atof(strings.trim_space(values[3])),
				strconv.atof(strings.trim_space(values[4])),
				strconv.atof(strings.trim_space(values[5])),
			},
		}
	}

	return hailstones
}

intersects :: proc(a, b: Hailstone, min_pos, max_pos: int) -> bool {
	d := b.position - a.position
	// fmt.println("d:", d)
	det := b.velocity.x * a.velocity.y - b.velocity.y * a.velocity.x
	// fmt.println("det:", det)

	if det == 0 {
		if a.position.x == b.position.x || a.position.y == b.position.y {
			// colinear
			// fmt.println(a, "is colinear with", b)
			return true
		}
		return false
	}

	u := (d.y * b.velocity.x - d.x * b.velocity.y) / det
	v := (d.y * a.velocity.x - d.x * a.velocity.y) / det

	if u >= 0 && v >= 0 {
		i := a.position + a.velocity * u
		// fmt.println(a, "intersects", b, "at", i)
		if i.x >= f64(min_pos) &&
		   i.x <= f64(max_pos) &&
		   i.y >= f64(min_pos) &&
		   i.y <= f64(max_pos) {
			return true
		}
	}

	return false
}

position_stone :: proc(
	hailstones: []Hailstone,
) -> (
	throw: Hailstone,
	solved: bool,
) {
	a := hailstones[0]
	b := hailstones[1]
	c := hailstones[2]

	fmt.println(a)
	fmt.println(b)
	fmt.println(c)

	mat: [6][6]f64 = {
		// equation 1: lines 0 and 1, x and y only
		 {
			a.velocity.y - b.velocity.y,
			b.velocity.x - a.velocity.x,
			0.0,
			b.position.y - a.position.y,
			a.position.x - b.position.x,
			0.0,
		},
		// equation 2: lines 0 and 2, x and y only
		 {
			a.velocity.y - c.velocity.y,
			c.velocity.x - a.velocity.x,
			0.0,
			c.position.y - a.position.y,
			a.position.x - c.position.x,
			0.0,
		},
		// equation 3: lines 0 and 1, x and z only
		 {
			a.velocity.z - b.velocity.z,
			0.0,
			b.velocity.x - a.velocity.x,
			b.position.z - a.position.z,
			0.0,
			a.position.x - b.position.x,
		},
		// equation 4: lines 0 and 2, x and z only
		 {
			a.velocity.z - c.velocity.z,
			0.0,
			c.velocity.x - a.velocity.x,
			c.position.z - a.position.z,
			0.0,
			a.position.x - c.position.x,
		},
		// equation 5: lines 0 and 1, y and z only
		 {
			0.0,
			a.velocity.z - b.velocity.z,
			b.velocity.y - a.velocity.y,
			0.0,
			b.position.z - a.position.z,
			a.position.y - b.position.y,
		},
		// equation 6: lines 0 and 2, y and z only
		 {
			0.0,
			a.velocity.z - c.velocity.z,
			c.velocity.y - a.velocity.y,
			0.0,
			c.position.z - a.position.z,
			a.position.y - c.position.y,
		},
	}

	fmt.println("mat:", mat)

	vec: [6]f64 = {
		// equation 1: lines 0 and 1, x and y only
		b.position.y * b.velocity.x -
		b.position.x * b.velocity.y -
		a.position.y * a.velocity.x +
		a.position.x * a.velocity.y,
		// equation 2: lines 0 and 2, x and y only
		c.position.y * c.velocity.x -
		c.position.x * c.velocity.y -
		a.position.y * a.velocity.x +
		a.position.x * a.velocity.y,
		// equation 3: lines 0 and 1, x and z only
		b.position.z * b.velocity.x -
		b.position.x * b.velocity.z -
		a.position.z * a.velocity.x +
		a.position.x * a.velocity.z,
		// equation 4: lines 0 and 2, x and z only
		c.position.z * c.velocity.x -
		c.position.x * c.velocity.z -
		a.position.z * a.velocity.x +
		a.position.x * a.velocity.z,
		// equation 5: lines 0 and 1, y and z only
		b.position.z * b.velocity.y -
		b.position.y * b.velocity.z -
		a.position.z * a.velocity.y +
		a.position.y * a.velocity.z,
		// equation 6: lines 0 and 2, y and z only
		c.position.z * c.velocity.y -
		c.position.y * c.velocity.z -
		a.position.z * a.velocity.y +
		a.position.y * a.velocity.z,
	}

	fmt.println("vec:", vec)

	solution, found := solve(mat, vec)
	if found {
		fmt.println("found solution:", solution)
	}

	return  {
			position = {solution[0], solution[1], solution[2]},
			velocity = {solution[3], solution[4], solution[5]},
		},
		found
}

// gaussian
solve :: proc(mat: [6][6]f64, vec: [6]f64) -> (p: [6]f64, solved: bool) {
	mat := mat
	vec := vec

	for i := 0; i < 6; i += 1 {
		m: int
		v: f64
		for j := i; j < 6; j += 1 {
			if math.abs(mat[j][i]) > v {
				v = math.abs(mat[j][i])
				m = j
			}
		}
		if math.abs(v) < 1e-10 do return
		tmp := vec[i]
		vec[i] = vec[m]
		vec[m] = tmp
		for j := 0; j < 6; j += 1 {
			tmp = mat[i][j]
			mat[i][j] = mat[m][j]
			mat[m][j] = tmp
		}

		// row reduction
		for n := i + 1; n < 6; n += 1 {
			r: f64 = mat[n][i] / mat[i][i]
			for k := i; k < 6; k += 1 {
				mat[n][k] -= r * mat[i][k]
			}
			vec[n] -= r * vec[i]
		}
	}

	for i := 5; i >= 0; i -= 1 {
		p[i] = vec[i]
		for j := i + 1; j < 6; j += 1 {
			p[i] -= mat[i][j] * p[j]
		}
		p[i] /= mat[i][i]
	}

	return p, true
}
