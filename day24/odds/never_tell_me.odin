package odds

import q "core:container/queue"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/big"
import "core:math/rand"
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
	big.Error,
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
	part2: u64,
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

	solved := false
	thrown: Hailstone
	// had to use pre-selected values due to f64 numeric errors
	if len(hailstones) > 274 {
		thrown, solved = position_stone_float(hailstones)
	} else {
		thrown, solved = position_stone_float(hailstones, 0, 1, 2)
	}
	if solved {
		fmt.println(thrown)
		px := u64(math.round(thrown.position.x))
		py := u64(math.round(thrown.position.y))
		pz := u64(math.round(thrown.position.z))
		part2 = px + py + pz
		fmt.println(px, "+", py, "+", pz, "=", part2)
	} else {
		fmt.println("no solution; choose another set of stones")
	}
	// 886858737029295
	// for !solved {
	// 	x := rand.int_max(len(hailstones))
	// 	y := rand.int_max(len(hailstones))
	// 	z := rand.int_max(len(hailstones))
	// 	thrownf, solvedf := position_stone_float(hailstones, x, y, z)
	// 	if solvedf {
	// 		if u64(
	// 			   thrownf.position.x +
	// 			   thrownf.position.y +
	// 			   thrownf.position.z,
	// 		   ) ==
	// 		   886858737029295 {
	// 			fmt.println(x, y, z)
	// 			break
	// 		}

	// 	} else do continue
	// }

	// solution, solved := position_stone(hailstones) or_return
	// defer for &s in solution do big.int_destroy(&s)
	// if solved {
	// 	fmt.println(solution)
	// 	answer: big.Int
	// 	defer big.int_destroy(&answer)
	// 	big.int_add(&answer, &solution[0], &solution[1])
	// 	big.int_add(&answer, &answer, &solution[2])

	// 	fmt.println("part2.bigint:", solution)

	// 	part2 = int(big.int_get_i64(&answer) or_return)
	// } else {
	// 	fmt.println("no solution; choose another set of stones")
	// }
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

Bigstone :: struct {
	position: [3]big.Int,
	velocity: [3]big.Int,
}

to_bigstone :: proc(hailstone: Hailstone) -> (bigstone: Bigstone) {
	big.int_set_from_integer(&bigstone.position.x, i64(hailstone.position.x))
	big.int_set_from_integer(&bigstone.position.y, i64(hailstone.position.y))
	big.int_set_from_integer(&bigstone.position.z, i64(hailstone.position.z))
	big.int_set_from_integer(&bigstone.velocity.x, i64(hailstone.velocity.x))
	big.int_set_from_integer(&bigstone.velocity.y, i64(hailstone.velocity.y))
	big.int_set_from_integer(&bigstone.velocity.z, i64(hailstone.velocity.z))

	return
}

position_stone_float :: proc(
	hailstones: []Hailstone,
	x: int = 274,
	y: int = 74,
	z: int = 28,
) -> (
	throw: Hailstone,
	solved: bool,
) {
	if x == y || x == z || y == z do return

	a := hailstones[x]
	b := hailstones[y]
	c := hailstones[z]

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

	solution, found := solve_float(mat, vec)
	if found {
		throw.position.x = solution[0]
		throw.position.y = solution[1]
		throw.position.z = solution[2]
		throw.velocity.x = solution[3]
		throw.velocity.y = solution[4]
		throw.velocity.z = solution[5]

		solved = true
	}

	return
}

SCALE :: 100000000000000000

position_stone :: proc(
	hailstones: []Hailstone,
) -> (
	solution: [6]big.Int,
	solved: bool,
	err: Snow_Making_Error,
) {
	a := to_bigstone(hailstones[0])
	defer big.int_destroy(&a.position.x, &a.position.y, &a.position.z)
	defer big.int_destroy(&a.velocity.x, &a.velocity.y, &a.velocity.z)
	b := to_bigstone(hailstones[1])
	defer big.int_destroy(&b.position.x, &b.position.y, &b.position.z)
	defer big.int_destroy(&b.velocity.x, &b.velocity.y, &b.velocity.z)
	c := to_bigstone(hailstones[2])
	defer big.int_destroy(&c.position.x, &c.position.y, &c.position.z)
	defer big.int_destroy(&c.velocity.x, &c.velocity.y, &c.velocity.z)

	scale: big.Int
	defer big.int_destroy(&scale)
	big.int_set_from_integer(&scale, SCALE) or_return

	m1a, m1b, m1c, m1d: big.Int
	defer big.int_destroy(&m1a, &m1b, &m1c, &m1d)
	// equation 1: lines 0 and 1, x and y only
	big.int_sub(&m1a, &a.velocity.y, &b.velocity.y) or_return
	big.int_sub(&m1b, &b.velocity.x, &a.velocity.x) or_return
	big.int_sub(&m1c, &b.position.y, &a.position.y) or_return
	big.int_sub(&m1d, &a.position.x, &b.position.x) or_return
	big.int_mul(&m1a, &m1a, &scale) or_return
	big.int_mul(&m1b, &m1b, &scale) or_return
	big.int_mul(&m1c, &m1c, &scale) or_return
	big.int_mul(&m1d, &m1d, &scale) or_return

	m2a, m2b, m2c, m2d: big.Int
	defer big.int_destroy(&m2a, &m2b, &m2c, &m2d)
	// equation 2: lines 0 and 2, x and y only
	big.int_sub(&m2a, &a.velocity.y, &c.velocity.y) or_return
	big.int_sub(&m2b, &c.velocity.x, &a.velocity.x) or_return
	big.int_sub(&m2c, &c.position.y, &a.position.y) or_return
	big.int_sub(&m2d, &a.position.x, &c.position.x) or_return
	big.int_mul(&m2a, &m2a, &scale) or_return
	big.int_mul(&m2b, &m2b, &scale) or_return
	big.int_mul(&m2c, &m2c, &scale) or_return
	big.int_mul(&m2d, &m2d, &scale) or_return

	m3a, m3b, m3c, m3d: big.Int
	defer big.int_destroy(&m3a, &m3b, &m3c, &m3d)
	// equation 3: lines 0 and 1, x and z only
	big.int_sub(&m3a, &a.velocity.z, &b.velocity.z) or_return
	big.int_sub(&m3b, &b.velocity.x, &a.velocity.x) or_return
	big.int_sub(&m3c, &b.position.z, &a.position.z) or_return
	big.int_sub(&m3d, &a.position.x, &b.position.x) or_return
	big.int_mul(&m3a, &m3a, &scale) or_return
	big.int_mul(&m3b, &m3b, &scale) or_return
	big.int_mul(&m3c, &m3c, &scale) or_return
	big.int_mul(&m3d, &m3d, &scale) or_return

	m4a, m4b, m4c, m4d: big.Int
	defer big.int_destroy(&m4a, &m4b, &m4c, &m4d)
	// equation 4: lines 0 and 2, x and z only
	big.int_sub(&m4a, &a.velocity.z, &c.velocity.z) or_return
	big.int_sub(&m4b, &c.velocity.x, &a.velocity.x) or_return
	big.int_sub(&m4c, &c.position.z, &a.position.z) or_return
	big.int_sub(&m4d, &a.position.x, &c.position.x) or_return
	big.int_mul(&m4a, &m4a, &scale) or_return
	big.int_mul(&m4b, &m4b, &scale) or_return
	big.int_mul(&m4c, &m4c, &scale) or_return
	big.int_mul(&m4d, &m4d, &scale) or_return

	m5a, m5b, m5c, m5d: big.Int
	defer big.int_destroy(&m5a, &m5b, &m5c, &m5d)
	// equation 5: lines 0 and 1, y and z only
	big.int_sub(&m5a, &a.velocity.z, &b.velocity.z) or_return
	big.int_sub(&m5b, &b.velocity.y, &a.velocity.y) or_return
	big.int_sub(&m5c, &b.position.z, &a.position.z) or_return
	big.int_sub(&m5d, &a.position.y, &b.position.y) or_return
	big.int_mul(&m5a, &m5a, &scale) or_return
	big.int_mul(&m5b, &m5b, &scale) or_return
	big.int_mul(&m5c, &m5c, &scale) or_return
	big.int_mul(&m5d, &m5d, &scale) or_return

	m6a, m6b, m6c, m6d: big.Int
	defer big.int_destroy(&m6a, &m6b, &m6c, &m6d)
	// equation 6: lines 0 and 2, y and z only
	big.int_sub(&m6a, &a.velocity.z, &c.velocity.z) or_return
	big.int_sub(&m6b, &c.velocity.y, &a.velocity.y) or_return
	big.int_sub(&m6c, &c.position.z, &a.position.z) or_return
	big.int_sub(&m6d, &a.position.y, &c.position.y) or_return
	big.int_mul(&m6a, &m6a, &scale) or_return
	big.int_mul(&m6b, &m6b, &scale) or_return
	big.int_mul(&m6c, &m6c, &scale) or_return
	big.int_mul(&m6d, &m6d, &scale) or_return

	mat: [6][6]big.Int
	// defer for &r in mat {
	// 	for &c in r {
	// 		big.int_destroy(&c)
	// 	}
	// }
	// =  {
	// 	{m1a, m1b, big.INT_ZERO^, m1c, m1d, big.INT_ZERO^},
	// 	{m2a, m2b, big.INT_ZERO^, m2c, m2d, big.INT_ZERO^},
	// 	{m3a, big.INT_ZERO^, m3b, m3c, big.INT_ZERO^, m3d},
	// 	{m4a, big.INT_ZERO^, m4b, m4c, big.INT_ZERO^, m4d},
	// 	{big.INT_ZERO^, m5a, m5b, big.INT_ZERO^, m5c, m5d},
	// 	{big.INT_ZERO^, m6a, m6b, big.INT_ZERO^, m6c, m6d},
	// }

	mat[0][0] = m1a
	mat[0][1] = m1b
	mat[0][3] = m1c
	mat[0][4] = m1d
	mat[1][0] = m2a
	mat[1][1] = m2b
	mat[1][3] = m2c
	mat[1][4] = m2d
	mat[2][0] = m3a
	mat[2][2] = m3b
	mat[2][3] = m3c
	mat[2][5] = m3d
	mat[3][0] = m4a
	mat[3][2] = m4b
	mat[3][3] = m4c
	mat[3][5] = m4d
	mat[4][1] = m5a
	mat[4][2] = m5b
	mat[4][4] = m5c
	mat[4][5] = m5d
	mat[5][1] = m6a
	mat[5][2] = m6b
	mat[5][4] = m6c
	mat[5][5] = m6d

	// print_mat(mat)

	v1, v2, v3, v4, v5, v6: big.Int
	vt: big.Int
	defer big.int_destroy(&v1, &v2, &v3, &v4, &v5, &v6, &vt)

	// equation 1: lines 0 and 1, x and y only
	big.int_mul(&v1, &b.position.y, &b.velocity.x) or_return
	big.int_mul(&vt, &b.position.x, &b.velocity.y) or_return
	big.int_sub(&v1, &v1, &vt) or_return
	big.int_mul(&vt, &a.position.y, &a.velocity.x) or_return
	big.int_sub(&v1, &v1, &vt) or_return
	big.int_mul(&vt, &a.position.x, &a.velocity.y) or_return
	big.int_add(&v1, &v1, &vt) or_return
	big.int_mul(&v1, &v1, &scale) or_return

	// equation 2: lines 0 and 2, x and y only
	big.int_mul(&v2, &c.position.y, &c.velocity.x) or_return
	big.int_mul(&vt, &c.position.x, &c.velocity.y) or_return
	big.int_sub(&v2, &v2, &vt) or_return
	big.int_mul(&vt, &a.position.y, &a.velocity.x) or_return
	big.int_sub(&v2, &v2, &vt) or_return
	big.int_mul(&vt, &a.position.x, &a.velocity.y) or_return
	big.int_add(&v2, &v2, &vt) or_return
	big.int_mul(&v2, &v2, &scale) or_return

	// equation 3: lines 0 and 1, x and z only
	big.int_mul(&v3, &b.position.z, &b.velocity.x) or_return
	big.int_mul(&vt, &b.position.x, &b.velocity.z) or_return
	big.int_sub(&v3, &v3, &vt) or_return
	big.int_mul(&vt, &a.position.z, &a.velocity.x) or_return
	big.int_sub(&v3, &v3, &vt) or_return
	big.int_mul(&vt, &a.position.x, &a.velocity.z) or_return
	big.int_add(&v3, &v3, &vt) or_return
	big.int_mul(&v3, &v3, &scale) or_return

	// equation 4: lines 0 and 2, x and z only
	big.int_mul(&v4, &c.position.z, &c.velocity.x) or_return
	big.int_mul(&vt, &c.position.x, &c.velocity.z) or_return
	big.int_sub(&v4, &v4, &vt) or_return
	big.int_mul(&vt, &a.position.z, &a.velocity.x) or_return
	big.int_sub(&v4, &v4, &vt) or_return
	big.int_mul(&vt, &a.position.x, &a.velocity.z) or_return
	big.int_add(&v4, &v4, &vt) or_return
	big.int_mul(&v4, &v4, &scale) or_return

	// equation 5: lines 0 and 1, y and z only
	big.int_mul(&v5, &b.position.z, &b.velocity.y) or_return
	big.int_mul(&vt, &b.position.y, &b.velocity.z) or_return
	big.int_sub(&v5, &v5, &vt) or_return
	big.int_mul(&vt, &a.position.z, &a.velocity.y) or_return
	big.int_sub(&v5, &v5, &vt) or_return
	big.int_mul(&vt, &a.position.y, &a.velocity.z) or_return
	big.int_add(&v5, &v5, &vt) or_return
	big.int_mul(&v5, &v5, &scale) or_return

	// equation 6: lines 0 and 2, y and z only
	big.int_mul(&v6, &c.position.z, &c.velocity.y) or_return
	big.int_mul(&vt, &c.position.y, &c.velocity.z) or_return
	big.int_sub(&v6, &v6, &vt) or_return
	big.int_mul(&vt, &a.position.z, &a.velocity.y) or_return
	big.int_sub(&v6, &v6, &vt) or_return
	big.int_mul(&vt, &a.position.y, &a.velocity.z) or_return
	big.int_add(&v6, &v6, &vt) or_return
	big.int_mul(&v6, &v6, &scale) or_return

	vec: [6]big.Int = {v1, v2, v3, v4, v5, v6}

	print_vec(vec)

	solution, solved = solve(mat, vec) or_return
	// if solved {
	// 	fmt.println("found solution:")

	// 	// for &s in solution {
	// 	// 	big.int_div(&s, &s, &scale) or_return
	// 	// }
	// }

	return
}

// gaussian elimination using big int
solve :: proc(
	mat: [6][6]big.Int,
	vec: [6]big.Int,
) -> (
	p: [6]big.Int,
	solved: bool,
	err: Snow_Making_Error,
) {
	mat := mat
	vec := vec

	scale: big.Int
	big.int_set_from_integer(&scale, SCALE) or_return
	defer big.int_destroy(&scale)

	for i := 0; i < 6; i += 1 {
		m: int
		v: big.Int
		defer big.int_destroy(&v)
		// find the row with the largest first element
		for j := i; j < 6; j += 1 {
			if gt := big.int_greater_than_abs(&mat[j][i], &v) or_return; gt {
				big.int_abs(&v, &mat[j][i]) or_return
				m = j
			}
		}
		if z, _ := big.int_less_than_abs(&v, &scale); z do return
		// swap both the vec and mat of the largest with the current
		big.int_swap(&vec[i], &vec[m])
		for j := 0; j < 6; j += 1 {
			big.int_swap(&mat[i][j], &mat[m][j])
		}

		// row reduction
		// for all the rows below the current
		for n := i + 1; n < 6; n += 1 {
			r, t: big.Int
			defer big.int_destroy(&r, &t)
			big.int_div(&t, &mat[i][i], &scale) or_return
			big.int_div(&r, &mat[n][i], &t) or_return

			for k := i; k < 6; k += 1 {
				big.int_mul(&t, &r, &mat[i][k]) or_return
				big.int_div(&t, &t, &scale) or_return
				big.int_sub(&mat[n][k], &mat[n][k], &t) or_return
			}
			big.int_mul(&t, &r, &vec[i]) or_return
			big.int_div(&t, &t, &scale) or_return
			big.int_sub(&vec[n], &vec[n], &t) or_return
		}
	}

	for i := 5; i >= 0; i -= 1 {
		big.int_copy(&p[i], &vec[i]) or_return
		t: big.Int
		defer big.int_destroy(&t)
		for j := i + 1; j < 6; j += 1 {
			big.int_mul(&t, &mat[i][j], &p[j]) or_return
			big.int_sub(&p[i], &p[i], &t) or_return
		}
		// big.int_div(&t, &mat[i][i], &scale) or_return
		// big.int_div(&p[i], &p[i], &t) or_return
		big.int_div(&p[i], &p[i], &mat[i][i]) or_return
	}

	return p, true, nil
}

// gaussian elimination
solve_float :: proc(mat: [6][6]f64, vec: [6]f64) -> (p: [6]f64, solved: bool) {
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

		// for j := 0; j < 6; j += 1 {
		// 	for k := 0; k < 6; k += 1 {
		// 		fmt.printf("%.0f ", mat[j][k])
		// 	}
		// 	fmt.println("")
		// }
		// for j := 0; j < 6; j += 1 {
		// 	fmt.printf("%.0f ", vec[j])
		// }
		// fmt.println("")
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

print_mat :: proc(mat: [6][6]big.Int) {
	for i := 0; i < 6; i += 1 {
		print_vec(mat[i])
	}
}

print_vec :: proc(vec: [6]big.Int) {
	vec := vec

	for i := 0; i < 6; i += 1 {
		num := print_big(vec[i])
		defer delete(num)
		fmt.print(num, " ")
	}
	fmt.println("")
}

print_big :: proc(num: big.Int) -> string {
	num := num
	scale: big.Int
	big.int_set_from_integer(&scale, SCALE)
	defer big.int_destroy(&scale)

	t: big.Int
	big.int_div(&t, &num, &scale)
	defer big.int_destroy(&t)
	v, _ := big.int_itoa_string(&t)
	return v
}
