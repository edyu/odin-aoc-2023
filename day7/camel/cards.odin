package boat

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

Hand_Error :: union {
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

Card :: enum {
	H2,
	H3,
	H4,
	H5,
	H6,
	H7,
	H8,
	H9,
	T,
	J,
	Q,
	K,
	A,
}

Card_Map := map[rune]Card {
	'2' = Card.H2,
	'3' = Card.H3,
	'4' = Card.H4,
	'5' = Card.H5,
	'6' = Card.H6,
	'7' = Card.H7,
	'8' = Card.H8,
	'9' = Card.H9,
	'T' = Card.T,
	'J' = Card.J,
	'Q' = Card.Q,
	'K' = Card.K,
	'A' = Card.A,
}

Hand_Type :: enum {
	High_Card,
	One_Pair,
	Two_Pair,
	Three_of_a_Kind,
	Full_House,
	Four_of_a_Kind,
	Five_of_a_Kind,
}

Hand :: struct {
	cards: [5]Card,
	bid:   int,
	type:  Hand_Type,
	rank:  int,
	order: int,
}

Game :: struct {
	num:   int,
	five:  [dynamic]Hand,
	four:  [dynamic]Hand,
	house: [dynamic]Hand,
	three: [dynamic]Hand,
	two:   [dynamic]Hand,
	one:   [dynamic]Hand,
	high:  [dynamic]Hand,
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
		fmt.printf("Usage: camel <file>\n")
		os.exit(1)
	}
	filename := arguments[0]

	win1, win2, error := process_file(filename)
	if error != nil {
		fmt.eprintf("Error while processing file '%s': %v\n", filename, error)
		os.exit(1)
	}
	fmt.printf("answer: part1 = %d part2 = %d\n", win1, win2)
}

process_file :: proc(filename: string) -> (win1: int, win2: int, err: Hand_Error) {
	data, ok := os.read_entire_file(filename)
	if !ok {
		return 0, 0, Unable_To_Read_File{filename = filename}
	}
	defer delete(data)

	it := string(data)
	lines := strings.split_lines(it)
	defer delete(lines)
	hands, hands2 := get_hands(lines) or_return
	defer delete(hands.five)
	defer delete(hands.four)
	defer delete(hands.house)
	defer delete(hands.three)
	defer delete(hands.two)
	defer delete(hands.one)
	defer delete(hands.high)
	defer delete(hands2.five)
	defer delete(hands2.four)
	defer delete(hands2.house)
	defer delete(hands2.three)
	defer delete(hands2.two)
	defer delete(hands2.one)
	defer delete(hands2.high)

	for h in hands.five {
		win1 += h.bid * h.rank
	}
	for h in hands.four {
		win1 += h.bid * h.rank
	}
	for h in hands.house {
		win1 += h.bid * h.rank
	}
	for h in hands.three {
		win1 += h.bid * h.rank
	}
	for h in hands.two {
		win1 += h.bid * h.rank
	}
	for h in hands.one {
		win1 += h.bid * h.rank
	}
	for h in hands.high {
		win1 += h.bid * h.rank
	}

	for h in hands2.five {
		win2 += h.bid * h.rank
	}
	for h in hands2.four {
		win2 += h.bid * h.rank
	}
	for h in hands2.house {
		win2 += h.bid * h.rank
	}
	for h in hands2.three {
		win2 += h.bid * h.rank
	}
	for h in hands2.two {
		win2 += h.bid * h.rank
	}
	for h in hands2.one {
		win2 += h.bid * h.rank
	}
	for h in hands2.high {
		win2 += h.bid * h.rank
	}

	return win1, win2, nil
}

compare_hands :: proc(a, b: Hand) -> bool {
	for i := 0; i < 5; i += 1 {
		if a.cards[i] == b.cards[i] do continue
		else do return a.cards[i] < b.cards[i]
	}
	return false
}

compare_hands2 :: proc(a, b: Hand) -> bool {
	for i := 0; i < 5; i += 1 {
		if a.cards[i] == b.cards[i] do continue
		if a.cards[i] == Card.J do return true
		else if b.cards[i] == Card.J do return false
		else do return a.cards[i] < b.cards[i]
	}
	return false
}

get_hands :: proc(lines: []string) -> (hands: Game, hands2: Game, err: Hand_Error) {
	for i := 0; i < len(lines); i += 1 {
		if lines[i] == "" do break
		line_fields := strings.split(lines[i], " ")
		defer delete(line_fields)
		assert(len(line_fields) == 2)
		hand_string := line_fields[0]
		bid_string := line_fields[1]
		hand: Hand
		hand2: Hand
		for h, j in hand_string {
			hand.cards[j] = Card_Map[h]
			hand2.cards[j] = Card_Map[h]
		}
		hand.type = analyze_hand(hand.cards)
		hand2.type = analyze_hand2(hand2.cards)
		hand.bid = strconv.atoi(bid_string)
		hand2.bid = hand.bid
		hand.order = i
		hand2.order = i

		switch hand.type {
		case Hand_Type.Five_of_a_Kind:
			append(&hands.five, hand)
		case Hand_Type.Four_of_a_Kind:
			append(&hands.four, hand)
		case Hand_Type.Full_House:
			append(&hands.house, hand)
		case Hand_Type.Three_of_a_Kind:
			append(&hands.three, hand)
		case Hand_Type.Two_Pair:
			append(&hands.two, hand)
		case Hand_Type.One_Pair:
			append(&hands.one, hand)
		case Hand_Type.High_Card:
			append(&hands.high, hand)
		}

		switch hand2.type {
		case Hand_Type.Five_of_a_Kind:
			append(&hands2.five, hand2)
		case Hand_Type.Four_of_a_Kind:
			append(&hands2.four, hand2)
		case Hand_Type.Full_House:
			append(&hands2.house, hand2)
		case Hand_Type.Three_of_a_Kind:
			append(&hands2.three, hand2)
		case Hand_Type.Two_Pair:
			append(&hands2.two, hand2)
		case Hand_Type.One_Pair:
			append(&hands2.one, hand2)
		case Hand_Type.High_Card:
			append(&hands2.high, hand2)
		}

		hands.num += 1
	}
	hands2.num = hands.num

	score_hands(&hands, compare_hands)
	score_hands(&hands2, compare_hands2)

	return hands, hands2, nil
}

score_hands :: proc(hands: ^Game, compare_hands_func: proc(a, b: Hand) -> bool) {
	score := hands.num + 1 - len(hands.five)
	slice.sort_by(hands.five[:], compare_hands_func)
	for &c, i in hands.five {
		c.rank = score + i
	}
	score -= len(hands.four)
	slice.sort_by(hands.four[:], compare_hands_func)
	for &c, i in hands.four {
		c.rank = score + i
	}
	score -= len(hands.house)
	slice.sort_by(hands.house[:], compare_hands_func)
	for &c, i in hands.house {
		c.rank = score + i
	}
	slice.sort_by(hands.three[:], compare_hands_func)
	score -= len(hands.three)
	for &c, i in hands.three {
		c.rank = score + i
	}
	slice.sort_by(hands.two[:], compare_hands_func)
	score -= len(hands.two)
	for &c, i in hands.two {
		c.rank = score + i
	}
	slice.sort_by(hands.one[:], compare_hands_func)
	score -= len(hands.one)
	for &c, i in hands.one {
		c.rank = score + i
	}
	slice.sort_by(hands.high[:], compare_hands_func)
	for &c, i in hands.high {
		c.rank = 1 + i
	}
}

analyze_hand :: proc(cards: [5]Card) -> Hand_Type {
	hand: map[Card]int
	defer delete(hand)
	for i := 0; i < 5; i += 1 {
		hand[cards[i]] += 1
	}
	switch len(hand) {
	case 1:
		return Hand_Type.Five_of_a_Kind
	case 2:
		for c in hand {
			if hand[c] == 4 do return Hand_Type.Four_of_a_Kind
			if hand[c] == 3 || hand[c] == 2 do return Hand_Type.Full_House
		}
	case 3:
		for c in hand {
			if hand[c] == 3 do return Hand_Type.Three_of_a_Kind
			if hand[c] == 2 do return Hand_Type.Two_Pair
		}
	case 4:
		return Hand_Type.One_Pair
	}
	return Hand_Type.High_Card
}

analyze_hand2 :: proc(cards: [5]Card) -> Hand_Type {
	hand: map[Card]int
	defer delete(hand)
	for i := 0; i < 5; i += 1 {
		hand[cards[i]] += 1
	}
	if hand[Card.J] == 0 {
		switch len(hand) {
		case 1:
			return Hand_Type.Five_of_a_Kind
		case 2:
			for c in hand {
				if hand[c] == 4 do return Hand_Type.Four_of_a_Kind
				if hand[c] == 3 || hand[c] == 2 do return Hand_Type.Full_House
			}
		case 3:
			for c in hand {
				if hand[c] == 3 do return Hand_Type.Three_of_a_Kind
				if hand[c] == 2 do return Hand_Type.Two_Pair
			}
		case 4:
			return Hand_Type.One_Pair
		}
		return Hand_Type.High_Card
	} else {
		num_j := hand[Card.J]
		switch len(hand) {
		case 1:
			return Hand_Type.Five_of_a_Kind
		case 2:
			for c in hand {
				if num_j > 0 do return Hand_Type.Five_of_a_Kind
				if hand[c] == 4 do return Hand_Type.Four_of_a_Kind
				if hand[c] == 3 || hand[c] == 2 do return Hand_Type.Full_House
			}
		case 3:
			if num_j >= 2 do return Hand_Type.Four_of_a_Kind
			for c in hand {
				if hand[c] == 3 {
					if num_j > 0 do return Hand_Type.Four_of_a_Kind
					return Hand_Type.Three_of_a_Kind
				}
				if hand[c] == 2 {
					if num_j > 0 do return Hand_Type.Full_House
					return Hand_Type.Two_Pair
				}
			}
		case 4:
			if num_j > 0 do return Hand_Type.Three_of_a_Kind
			return Hand_Type.One_Pair
		}
		if num_j > 0 do return Hand_Type.One_Pair
		return Hand_Type.High_Card
	}
}

