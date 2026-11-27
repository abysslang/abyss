#!/usr/bin/env bash
set -euo pipefail

compiler=$1
work=$2
mkdir -p "$work"

cat > "$work/helper.a" <<'ABYSS'
combine :: extern fn(a, b, c, d, e, f i32) i32 {
    a + b * 2 + c * 3 + d * 4 + e * 5 + f * 6
}
ABYSS

cat > "$work/main.a" <<'ABYSS'
combine :: extern fn(i32, i32, i32, i32, i32, i32) i32
counter: i32 = 2

main :: fn() i32 {
    rounds := 0
    while rounds < 3 {
        counter = counter + rounds
        rounds = rounds + 1
    }
    bytes := c"AB"
    if bytes[1] != 66 { ret 90 }
    if ((127 as i8) + (1 as i8)) as i32 != -128 { ret 91 }
    if ((-4 as i16) >> 1) as i32 != -2 { ret 92 }
    if (0 - (1 as u64)) <= 1 { ret 93 }
    if ((-13 as i32) / 4) != -3 or ((-13 as i32) % 4) != -1 { ret 94 }
    buffer: [4]u8 = .[1, 2, 3, 4]
    @memcpy(&buffer[1], &buffer[0], 3)
    if buffer[1] != 1 or buffer[3] != 3 { ret 95 }
    @memcpy(&buffer[0], &buffer[1], 3)
    if buffer[0] != 1 or buffer[2] != 3 { ret 96 }
    base := if counter == 5 { combine(1, 1, 1, 1, 1, 1) } else { 0 }
    base * 2
}
ABYSS

options=(b --target linux --arch x86_64 --emit-obj)
"$compiler" "${options[@]}" --library "$work/helper.a" "$work/helper.o"
PATH=/nonexistent "$compiler" "${options[@]}" "$work/main.a" "$work/main.o"
"$compiler" "${options[@]}" "$work/main.a" "$work/repeat.o"
cmp "$work/main.o" "$work/repeat.o"
ld -o "$work/main" "$work/main.o" "$work/helper.o"
status=0
timeout 5s "$work/main" || status=$?
[[ "$status" == 42 ]]

cat > "$work/float.a" <<'ABYSS'
scale :: fn(x f64) f64 { x + 0.5 }
main :: fn() i32 { scale(1.0) as i32 }
ABYSS
"$compiler" "${options[@]}" "$work/float.a" "$work/float.o"
ld -o "$work/float" "$work/float.o"
status=0
timeout 5s "$work/float" || status=$?
[[ "$status" == 1 ]]

cat > "$work/registers.a" <<'ABYSS'
add :: extern fn(left, right i64) i64 { left + right }
step :: fn(value f64) f64 { value + 1.0 }

integer_pressure :: fn(one, two, three, four, five, six, seven, eight, nine, ten i64) i64 {
    sum := add(one, ten)
    sum + one + two + three + four + five + six + seven + eight + nine + ten
}

float_pressure :: fn(one, two, three, four, five, six, seven, eight, nine, ten f64) f64 {
    sum := step(one)
    sum + one + two + three + four + five + six + seven + eight + nine + ten
}

rotate :: fn(first, second, rounds i64) i64 {
    left := first
    right := second
    count := rounds
    while count > 0 {
        saved := left
        left = right
        right = saved
        count = count - 1
    }
    left * 10 + right
}

main :: fn() i32 {
    if integer_pressure(1, 2, 3, 4, 5, 6, 7, 8, 9, 10) != 66 { ret 91 }
    if float_pressure(1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0) != 57.0 { ret 92 }
    if rotate(2, 7, 3) != 72 or rotate(2, 7, 4) != 27 { ret 93 }
    0
}
ABYSS
"$compiler" "${options[@]}" "$work/registers.a" "$work/registers.o"
ld -o "$work/registers" "$work/registers.o"
timeout 5s "$work/registers"
if command -v objdump > /dev/null; then
    add_code=$(objdump -d --disassemble=add "$work/registers.o")
    [[ "$add_code" == *addq* || "$add_code" == *$'\tadd '* ]]
    [[ "$add_code" != *'(%rbp)'* ]]
fi

cat > "$work/initialized.a" <<'ABYSS'
value: i32 = 42
stored :: extern fn() i32 { value }
ABYSS
cat > "$work/hosted.a" <<'ABYSS'
stored :: extern fn() i32
main :: fn() i32 {
    high := (1 as u64) << 63
    real := high as f64
    if (real as u64) != high { ret 91 }
    zero := -0.0
    if zero as bool { ret 92 }
    a := (1 as i128) << 100
    b := a / 2
    if b != (a >> 1) or (b * 2) != a or b >= a { ret 93 }
    if ((b as f64) as i128) != b { ret 94 }
    stored()
}
ABYSS
"$compiler" "${options[@]}" --library "$work/initialized.a" "$work/initialized.o"
"$compiler" "${options[@]}" --hosted "$work/hosted.a" "$work/hosted.o"
bash "$(dirname "${BASH_SOURCE[0]}")/link_object.sh" "$work/hosted.o" "$work/initialized.o" -o "$work/hosted"
status=0
timeout 5s "$work/hosted" || status=$?
[[ "$status" == 42 ]]
