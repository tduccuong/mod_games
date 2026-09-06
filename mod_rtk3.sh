#!/usr/bin/env bash
#
# mod_rtk3.sh -- Maximize city resources, army stats, and character skills in
#                a Romance of the Three Kingdoms III (KOEI, 1992/1993 DOS/
#                PC-98 port, English fan-translated .SAV) save file.
#
# USAGE:
#   ./mod_rtk3.sh --input FILE [--output FILE]
#                 [--ruler NAME] [--city NAME_OR_NUMBER]
#                 [--bump-officer NAME]...
#                 [--bump-officers-for-ruler NAME]...
#                 [--no-auto-ruler]
#
#   Just "--city NAME_OR_NUMBER" by itself is enough to max out that city
#   AND every officer garrisoned there -- no ruler name required. Every run
#   auto-detects your own character(s) from the save's character-creation
#   roster and maxes their garrisons too; see "AUTO-DETECTING YOUR RULER"
#   further down. Pass --no-auto-ruler to turn that off.
#
#   --input FILE (required)     Path to a SANGOKU3.SAV (or backup copy).
#   --output FILE                Output path. Defaults to "<input>.maxed.sav",
#                                 in which case --input is NEVER touched (the
#                                 game keeps loading the old, unmaxed file
#                                 until you rename/copy the .maxed.sav output
#                                 over it yourself -- this is the #1 cause of
#                                 "I ran the script but nothing changed").
#                                 Pass --output pointing at the SAME path as
#                                 --input to mod the save in place; in that
#                                 case the script automatically makes a
#                                 timestamped "<input>.autobak-<timestamp>"
#                                 copy of the original first, every run.
#   --ruler NAME                 Max this ruler's 6 skill stats (Army Command,
#                                 Navy Command, War, Intelligence, Politics,
#                                 Charm). Exact in-game spelling, case-sensitive.
#   --city NAME_OR_NUMBER         Max this city's resources/dev stats. Either
#                                 the in-game name ("Jin Yang") or its map
#                                 number (4), resolved via CITY_NAMES below.
#   --bump-officer NAME           Max one specific officer's 6 skill stats and
#                                 their personal Soldiers count. Repeatable.
#   --bump-officers-for-ruler NAME
#                                 Max stats + Soldiers for every officer found
#                                 stationed alongside the named ruler (see
#                                 "SCOPE" note below -- this is NOT every
#                                 officer in that ruler's whole kingdom).
#                                 Repeatable.
#
#   At least one of --ruler / --city / --bump-officer / --bump-officers-for-ruler
#   must be given.
#
# EXAMPLES:
#   ./mod_rtk3.sh --input SANGOKU3.SAV.modbackup --ruler "CUONG TRUONG" --city 4
#
#   ./mod_rtk3.sh --input SANGOKU3.SAV.modbackup --ruler "CUONG TRUONG" --city "Jin Yang" \
#                 --output SANGOKU3.SAV.maxed
#
#   # Just max one named general anywhere in the file, nothing else:
#   ./mod_rtk3.sh --input SANGOKU3.SAV.modbackup --bump-officer "Zhao Yun"
#
#   # Max the ruler's own skills AND every officer garrisoned with them:
#   ./mod_rtk3.sh --input SANGOKU3.SAV.modbackup --ruler "CUONG TRUONG" \
#                 --bump-officers-for-ruler "CUONG TRUONG"
#
# ============================================================================
# HOW THE SAVE FORMAT WAS REVERSE-ENGINEERED
# ============================================================================
# There is no public documentation of this save format. Every offset and
# field below was derived empirically:
#   1. hex/string scanning of SANGOKU3.SAV to locate candidate text (city
#      names, ruler name, item names) and repeating fixed-size records.
#   2. DOSBox was installed and the actual game was run against edited copies
#      of the save. A field was only considered "confirmed" once an edit to
#      it was reloaded in-game and the expected value appeared on the
#      correct screen (Rest menu resource bars, Info > Own city > City data,
#      Info > Own city > Officers data).
#   3. Fields marked CONFIRMED below were verified this way (write -> reload
#      -> observe). Nothing below was shipped on a guess alone.
#
# ============================================================================
# FILE LAYOUT SUMMARY
# ============================================================================
#
# --- City record (one per city, CONFIRMED 74 bytes each) -------------------
# City records live in a table that starts a little before offset 0x10000 in
# the save. Each record is 74 bytes. The city's display name is an ASCII,
# NUL-padded string sitting at relative offset +52 within its own record, so:
#
#     name_offset = byte offset where "Jin Yang" (etc) is found in the file
#     rec_start   = name_offset - 52
#
# Fields inside the 74-byte record, all offsets relative to rec_start
# (CONFIRMED = empirically verified via live edit + in-game reload):
#
#   +11..+12   Population / 100   (u16 LE)   CONFIRMED   e.g. stored 850 -> UI shows 85,000
#   +13..+14   Gold                (u16 LE)   CONFIRMED
#   +15..+18   Food                (u32 LE)   CONFIRMED
#   +29        Lnd  - Land development  (u8, ~0-100)           CONFIRMED
#   +30        Clt  - Culture/civil dev (u8, ~0-100)           CONFIRMED
#   +31        Irr  - Irrigation level  (u8, ~0-100)           high confidence (read-matched, byte isolated)
#   +32        FlC  - Flood control     (u8, ~0-100)           high confidence (read-matched, byte isolated)
#   +33..+34   Econ - Economy value     (u16 LE, signed display)  CONFIRMED
#   +35        Tax  - Tax rate          (u8, ~0-100)           high confidence (read-matched, byte isolated)
#   +36        PS   - Public Support    (u8, 0-100)            CONFIRMED
#   +37..+38   Crsb - Crossbow stockpile (u16 LE, signed display) CONFIRMED
#   +39..+40   Crst - unlabeled dev stat (u16 LE, signed display) CONFIRMED location (meaning unclear; UI just shows "Crst")
#   +41..+42   Hors - Horse stockpile    (u16 LE, signed display) CONFIRMED
#   +47..+51   Market buy/sell price quotes (NOT a stored resource -- these
#              fluctuate on their own; left untouched)
#   +52..+63   City name, ASCII, NUL padded
#
# IMPORTANT: several 2-byte fields (Crsb, Crst, Hors, Econ) are read by the
# "City data" info screen as SIGNED 16-bit integers. Setting them to 0xFFFF
# (65535) displays as a small negative number instead of "maxed". This
# script caps those fields at 32767 (0x7FFF) so every screen renders them as
# a huge, clean positive number. Population/Gold are read as UNSIGNED by the
# Rest-menu resource screen, so they safely use the full 65535 there -- but
# Population is ALSO read (incorrectly, as signed) by the City data screen,
# so it is likewise capped at 32767 to avoid a "-100"-style glitch there.
#
# "Soldiers" and "Off" (officer count) shown on the Rest-menu resource panel
# are NOT stored on the city record at all -- see the officer section below.
#
# --- Character records (ruler AND named officers, CONFIRMED) ---------------
# Character stat blocks appear in two different shapes in the file. Both are
# anchored by finding the character's name as literal ASCII text and reading
# backward from it (this works identically whether the name is a ruler or
# any other named officer -- see --bump-officer). There is no separate
# "signature" byte sequence -- the bytes immediately preceding the name in a
# valid record ARE the 6 stat values, so validity is checked by range (each
# of the 6 must be 1-100).
#
#   COMPACT record (stats end 9 bytes before the name starts):
#     name_offset-9 .. name_offset-4   : ArmyCmd, NavyCmd, War, Int, Politics, Charm  (u8 each, 0-100)
#     name_offset-3 .. name_offset-2   : unknown flags (left untouched)
#     name_offset-1                    : Age (u8, left untouched)
#   This shape is used by what looks like a "custom character roster"
#   template table (2 copies were found for the save's ruler). Editing only
#   this copy did NOT change what the running game displayed, but it is
#   patched anyway for safety/consistency in case anything re-syncs from it.
#
#   RICH record (stats end 39 bytes before the name starts):
#     name_offset-39 .. name_offset-34 : ArmyCmd, NavyCmd, War, Int, Politics, Charm  (u8 each, 0-100)
#     name_offset-39-11                : Soldiers, u16 LE -- see below
#   This is the shape actually read by the live game screens. This is the
#   copy that matters; CONFIRMED by editing it and seeing the Info screens
#   update. --bump-officer maxes this same 11-bytes-before-stats Soldiers
#   field for the named officer too (a real name resolves straight to their
#   own RICH record, no positional scanning needed).
#
# --- AUTO-DETECTING YOUR RULER (so --city alone is enough) -----------------
# There is no reverse-engineered field linking a city record to the person-
# table position of its governor/garrison (several hypotheses -- an index
# stored on the city record, a fixed per-city slot in the person table, a
# per-officer "assigned city" byte -- were tested against real save data and
# none held up; see git history for the investigation). So the city record
# alone cannot tell you where to find its officers.
#
# What DOES reliably work: the save's character-creation roster. "Create
# User Data" always writes your character(s) into a fixed table of 8
# 21-byte slots starting at offset 0x26; every unused slot is literally the
# placeholder text "New Ruler" (confirmed against the roster of the save
# used for testing, which had exactly one real name in slot 0 and 7
# placeholders). So: read those 8 slots, skip anything that reads "New
# Ruler", and whatever's left is your real character name(s) -- with no
# user input needed. Every run then automatically calls the same
# --bump-officers-for-ruler logic (positional scan from that name's RICH
# record) for each detected name, in addition to anything explicitly passed
# with --ruler/--bump-officer/--bump-officers-for-ruler. --no-auto-ruler
# disables this if you ever don't want it.
#
# This does NOT solve "find officers for city X" in general (a city
# governed by a random AI-generated officer you haven't named yourself still
# can't be targeted without knowing their name) -- it solves the much more
# common case of "find officers for MY city", since your own ruler is
# nearly always who the game considers to be governing wherever you're
# playing.
#
# --- Officer troop counts ("army" stats) (CONFIRMED for Soldiers) ----------
# The city's displayed "Sold:" total is NOT a field of the city record. It is
# the live sum of the personal troop counts of whichever officers/generals
# are stationed in that city. Each officer has their own RICH-shaped record
# (6 stats as above) and their personal Soldiers count sits 11 bytes BEFORE
# their stats block, as a u16 LE:
#
#     soldiers_offset = officer_stats_offset - 11        (u16 LE)  CONFIRMED
#
# In the save used to reverse-engineer this, character records (ruler and
# officers alike) sit in a table of fixed 69-byte "person slots". The ruler
# occupies 8 consecutive slots by itself (apparently extra per-ruler fields
# use the space of several plain slots), and the officers garrisoned with
# them then follow immediately: ruler at slot 0, officer A at slot 8,
# officer B at slot 9 (69*8 = 552 bytes and 69*9 = 621 bytes past the
# ruler's stats, respectively -- both confirmed exactly against the file).
# Because of that 8-slot dead zone, --bump-officers-for-ruler cannot simply
# stop at the first slot that fails to validate -- it would quit before ever
# reaching slot 8. Instead it scans a fixed window of slots (see
# SCAN_WINDOW_SLOTS below) forward from the ruler and independently
# validates each one: a slot whose next 6 bytes look like a valid stat block
# (1-100 each) AND whose 2 bytes 11 before that look like a plausible troop
# count (0-30000) is treated as a garrisoned officer, and its 6 skill stats
# plus its Soldiers field are maxed.
#
# SCOPE NOTE for --bump-officers-for-ruler: "officers under that ruler" here
# means officers positionally grouped with the ruler in this same slot
# table (in practice: the officers stationed in the ruler's own city/group).
# There is no reverse-engineered per-officer "kingdom" or "loyal to ruler X"
# byte, so this cannot reach officers in a ruler's OTHER cities if their
# kingdom holds more than one. It is exactly the same underlying scan the
# base --city/--ruler run already used to find that city's garrison.
#
# SAFETY NOTE for --bump-officer / --bump-officers-for-ruler / --ruler: names
# are matched by raw text search, and short/generic names risk coincidental
# matches elsewhere in a ~650KB binary file. This was NOT hypothetical --
# testing with the single-letter placeholder name "A" (used for an
# auto-generated officer with no real name) turned up 100+ raw matches
# across the file, almost all of them unrelated bytes that happened to spell
# "A". The script refuses to act on any name shorter than MIN_SAFE_NAME_LEN
# (4 characters) if it produced more than MAX_SAFE_HITS (5) raw matches,
# printing an error instead of silently touching the wrong data. Real named
# generals ("Zhao Yun", "Guan Yu", etc.) are long/specific enough that this
# has not been an issue in testing. Single-letter auto-generated officers
# (shown in-game just as "A", "B", ...) cannot be targeted by name at all --
# use --bump-officers-for-ruler on their ruler instead.
#
# Officer Training/Morale/Loyalty/Age fields were investigated but could NOT
# be pinned down with confidence in the time available (candidate bytes gave
# contradictory results between two different test officers) -- they are
# deliberately NOT touched by this script to avoid corrupting unrelated
# data. Soldiers is the one officer-level "army" field that was fully
# verified end-to-end.
#
# ============================================================================
# LIMITATIONS / NOT COVERED
# ============================================================================
#   - Every occurrence of a targeted name (compact + rich) gets its stats
#     maxed, to match the "bump everything to max" ask, but the forward
#     officer-scan (for --bump-officers-for-ruler) only runs from RICH
#     matches.
#   - City record fields at relative offsets +19..+28 and +43..+46 were
#     never mapped to any on-screen stat (Info screens showed no change when
#     probed) and are left untouched.
#   - --bump-officers-for-ruler is scoped to the ruler's own slot-group, not
#     their whole kingdom (see SCOPE NOTE above).
#   - This targets the English fan-translated DOS build used during
#     reverse-engineering. Offsets are byte-identical across saves from that
#     same game build, but a different release/translation could shift them.

set -euo pipefail

# ---------------------------------------------------------------------------
# City ID -> name table, extracted directly from the save's own city name
# table (order 1..46, matching the in-game map numbers shown next to each
# city, e.g. "4.Jin Yang").
# ---------------------------------------------------------------------------
CITY_NAMES=(
  "Xiang Ping" "Bei Ping" "Dai Xian" "Jin Yang" "Nan Pi" "Ping Yuan" "Ye"
  "Bei Hai" "Pu Yang" "Chen Liu" "Luo Yang" "Hong Nong" "Chang An" "An Ding"
  "Tian Shui" "Xi Liang" "Xia Pi" "Xu Zhou" "Xu Chang" "Qiao" "Ru Nan" "Wan"
  "Xin Ye" "Xiang Yang" "Shang Yong" "Jiang Xia" "Jiang Ling" "Wu Ling"
  "Chang Sha" "Gui Yang" "Ling Ling" "Shou Chun" "Jian Ye" "Wu" "Hui Ji"
  "Lu Jiang" "Chai Sang" "Han Zhong" "Xia Bian" "Zi Tong" "Cheng Du"
  "Yong An" "Jiang Zhou" "Jian Ning" "Yun Nan" "Nan Hai"
)

usage() {
  cat >&2 <<'EOF'
Usage: mod_rtk3.sh --input FILE [--output FILE]
                    [--ruler NAME] [--city NAME_OR_NUMBER]
                    [--bump-officer NAME]...
                    [--bump-officers-for-ruler NAME]...
                    [--no-auto-ruler]

At least one of --ruler / --city / --bump-officer / --bump-officers-for-ruler
is required. See the comments at the top of this script for full details.

By default, every run also auto-detects your custom character(s) from the
save's own character-creation roster and maxes their garrisons' skills +
Soldiers too (same as passing --bump-officers-for-ruler for each of them) --
so "--city 7" alone is enough, no ruler name required. Pass --no-auto-ruler
to turn this off.
EOF
  exit 1
}

IN_FILE=""
OUT_FILE=""
RULER_NAME=""
CITY_ARG=""
BUMP_OFFICERS=()
BUMP_OFFICERS_FOR_RULER=()
AUTO_RULER=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)  IN_FILE="$2"; shift 2 ;;
    --output) OUT_FILE="$2"; shift 2 ;;
    --ruler)  RULER_NAME="$2"; shift 2 ;;
    --city)   CITY_ARG="$2"; shift 2 ;;
    --bump-officer) BUMP_OFFICERS+=("$2"); shift 2 ;;
    --bump-officers-for-ruler) BUMP_OFFICERS_FOR_RULER+=("$2"); shift 2 ;;
    --no-auto-ruler) AUTO_RULER=0; shift 1 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -z "$IN_FILE" ]] && usage
[[ -f "$IN_FILE" ]] || { echo "Error: input file not found: $IN_FILE" >&2; exit 1; }
[[ -z "$OUT_FILE" ]] && OUT_FILE="${IN_FILE}.maxed.sav"

if [[ -z "$RULER_NAME" && -z "$CITY_ARG" && ${#BUMP_OFFICERS[@]} -eq 0 && ${#BUMP_OFFICERS_FOR_RULER[@]} -eq 0 ]]; then
  echo "Error: nothing to do -- give at least one of --ruler / --city / --bump-officer / --bump-officers-for-ruler" >&2
  usage
fi

# Resolve a numeric city argument to its name via the table above.
CITY_NAME="$CITY_ARG"
if [[ -n "$CITY_ARG" && "$CITY_ARG" =~ ^[0-9]+$ ]]; then
  idx=$((CITY_ARG - 1))
  if (( idx < 0 || idx >= ${#CITY_NAMES[@]} )); then
    echo "Error: city number $CITY_ARG out of range (1-${#CITY_NAMES[@]})" >&2
    exit 1
  fi
  CITY_NAME="${CITY_NAMES[$idx]}"
fi

echo "Input file : $IN_FILE"
echo "Output file: $OUT_FILE"
[[ -n "$RULER_NAME" ]] && echo "Ruler      : $RULER_NAME"
[[ -n "$CITY_NAME"  ]] && echo "City       : $CITY_NAME"
for n in "${BUMP_OFFICERS[@]:-}"; do [[ -n "$n" ]] && echo "Bump officer         : $n"; done
for n in "${BUMP_OFFICERS_FOR_RULER[@]:-}"; do [[ -n "$n" ]] && echo "Bump officers for ruler: $n"; done

# By default this script NEVER touches the input file -- it writes to a
# separate "<input>.maxed.sav" unless --output is given. The one case where
# it DOES overwrite something is if you explicitly pass --output pointing
# at the same file as --input (in-place mode). In that case, and only that
# case, take an automatic timestamped safety backup first so an in-place
# run is never a one-way door.
if [[ -e "$OUT_FILE" ]] && [[ "$(realpath "$IN_FILE")" == "$(realpath "$OUT_FILE")" ]]; then
  AUTO_BACKUP="${IN_FILE}.autobak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$IN_FILE" "$AUTO_BACKUP"
  echo "In-place run detected (--output == --input): auto-backed up original to $AUTO_BACKUP"
fi

python3 - "$IN_FILE" "$OUT_FILE" "$RULER_NAME" "$CITY_NAME" "$AUTO_RULER" \
    --officers "${BUMP_OFFICERS[@]:-}" \
    --officers-for-ruler "${BUMP_OFFICERS_FOR_RULER[@]:-}" <<'PYEOF'
import sys, struct

argv = sys.argv[1:]
in_path, out_path, ruler_name, city_name, auto_ruler_flag = argv[0:5]
auto_ruler = auto_ruler_flag == "1"
rest = argv[5:]

bump_officers = []
bump_officers_for_ruler = []
mode = None
for tok in rest:
    if tok == "--officers":
        mode = "officers"
        continue
    if tok == "--officers-for-ruler":
        mode = "for_ruler"
        continue
    if not tok:
        continue
    if mode == "officers":
        bump_officers.append(tok)
    elif mode == "for_ruler":
        bump_officers_for_ruler.append(tok)

with open(in_path, "rb") as f:
    data = bytearray(f.read())

def find_all(needle: bytes):
    pos = []
    start = 0
    while True:
        i = data.find(needle, start)
        if i == -1:
            break
        pos.append(i)
        start = i + 1
    return pos

def looks_like_stats(offset):
    """6 consecutive bytes, each a plausible 1-100 stat value."""
    if offset < 0 or offset + 6 > len(data):
        return False
    return all(1 <= data[offset + i] <= 100 for i in range(6))

MAX_SOLDIERS = 65535   # true u16 field max. Confirmed via live reload that
                        # this field is read UNSIGNED and the Rest-menu
                        # "Sold" bar/number both render cleanly at 65535 (no
                        # sign-flip glitch like the city record's signed
                        # fields). An earlier version of this script used
                        # 9999 here, which is only ~15% of the bar's actual
                        # range -- that's why the bar looked half-empty even
                        # after "maxing".
STRIDE = 69
SCAN_WINDOW_SLOTS = 40  # see header comment: ruler occupies 8 dead slots,
                         # officers follow; widened from an earlier value of
                         # 15 because a kingdom that has grown to hold
                         # several cities needs more dead/garrison slots
                         # scanned before reaching a later city's officers.

# ---------------------------------------------------------------------------
# Custom character roster (see header comment "AUTO-DETECTING YOUR RULER"):
# 8 fixed-width slots starting at a fixed offset, used by the game's
# "Create User Data" character creator. Unused slots are literally the
# placeholder text "New Ruler". Real slots hold whatever name you gave your
# character when you created them -- this is how --city alone can find your
# officers without you typing a name.
# ---------------------------------------------------------------------------
ROSTER_BASE = 0x26
ROSTER_STRIDE = 21
ROSTER_SLOTS = 8
ROSTER_PLACEHOLDER = b"New Ruler"

def detect_custom_ruler_names():
    names = []
    for i in range(ROSTER_SLOTS):
        off = ROSTER_BASE + i * ROSTER_STRIDE
        raw = data[off:off + ROSTER_STRIDE]
        end = raw.find(b"\x00")
        raw = raw[:end] if end != -1 else raw
        if raw and raw != ROSTER_PLACEHOLDER:
            try:
                names.append(raw.decode("ascii"))
            except UnicodeDecodeError:
                pass
    return names

changes = 0

def max_soldiers_at(stats_pos, label):
    """Max the Soldiers field 11 bytes before a validated RICH stats block."""
    global changes
    soldiers_off = stats_pos - 11
    if soldiers_off < 0:
        return
    current = struct.unpack_from("<H", data, soldiers_off)[0]
    if current > 30000:
        # doesn't look like a plausible troop count field; leave it alone.
        return
    struct.pack_into("<H", data, soldiers_off, MAX_SOLDIERS)
    changes += 1
    print(f"  {label} Soldiers maxed at 0x{soldiers_off:x} (was {current})")

MIN_SAFE_NAME_LEN = 4     # names shorter than this are too likely to
MAX_SAFE_HITS = 5         # coincidentally match unrelated bytes elsewhere
                          # in a ~650KB binary file -- see safe_name_hits().

def safe_name_hits(name, label):
    """find_all(name), but refuses to act on short/common names that
    produced a suspiciously large number of hits, to avoid silently
    corrupting unrelated records. Auto-generated placeholder officers like
    "A" or "B" are exactly the case this guards against: a 1-letter name
    can coincidentally match hundreds of unrelated byte sequences."""
    name_bytes = name.encode("ascii")
    hits = find_all(name_bytes)
    if not hits:
        print(f"WARNING: {label} {name!r} not found in file", file=sys.stderr)
        return []
    if len(name) < MIN_SAFE_NAME_LEN and len(hits) > MAX_SAFE_HITS:
        print(
            f"ERROR: {label} {name!r} is too short/common to search for safely -- "
            f"found {len(hits)} raw byte matches in the file, most of which are almost "
            f"certainly unrelated data, not real records. Refusing to touch any of them. "
            f"Use the character's full in-game name instead.",
            file=sys.stderr,
        )
        return []
    return hits

def bump_character(name, also_max_soldiers, label):
    """Find every occurrence of `name` and max whichever stat-block shape(s)
    surround it (COMPACT and/or RICH). Returns the list of RICH stats
    offsets found, so callers can do further positional scanning from them
    (see --bump-officers-for-ruler)."""
    global changes
    hits = safe_name_hits(name, label)
    if not hits:
        return []

    rich_positions = []
    for name_off in hits:
        compact_stats = name_off - 9
        rich_stats = name_off - 39

        if looks_like_stats(compact_stats):
            for i in range(6):
                data[compact_stats + i] = 100
            changes += 1
            print(f"  {label} {name!r} COMPACT stats patched at 0x{compact_stats:x}")

        if looks_like_stats(rich_stats):
            for i in range(6):
                data[rich_stats + i] = 100
            changes += 1
            print(f"  {label} {name!r} RICH stats patched at 0x{rich_stats:x}")
            rich_positions.append(rich_stats)
            if also_max_soldiers:
                max_soldiers_at(rich_stats, f"{label} {name!r}")

    return rich_positions

# ---------------------------------------------------------------------------
# 0. AUTO-DETECT YOUR RULER(S) so --city alone is enough (see header comment
#    "AUTO-DETECTING YOUR RULER"). Merge into bump_officers_for_ruler,
#    de-duplicated against anything already given explicitly.
# ---------------------------------------------------------------------------
if auto_ruler:
    detected = detect_custom_ruler_names()
    new_names = [n for n in detected if n not in bump_officers_for_ruler]
    if new_names:
        print(f"Auto-detected custom character(s) from save roster: {new_names} "
              f"-- also maxing their garrisons' skills + Soldiers (use --no-auto-ruler to disable)")
        bump_officers_for_ruler.extend(new_names)

# ---------------------------------------------------------------------------
# 1. CITY RESOURCES
# ---------------------------------------------------------------------------
if city_name:
    city_bytes = city_name.encode("ascii")
    city_hits = find_all(city_bytes)
    if not city_hits:
        print(f"WARNING: city name {city_name!r} not found in file -- skipping city edits", file=sys.stderr)

    for name_off in city_hits:
        rec_start = name_off - 52
        if rec_start < 0:
            continue
        # sanity check: the name should be followed by NUL padding (real
        # record), not running into other text (avoids false positives in
        # prose/messages). Only the first 7 bytes right after the name are
        # checked -- relative offsets +69/+70 (2 bytes right before each
        # record's 0xff 0xff marker) are a real, still-unmapped field that
        # varies per city (confirmed nonzero for some cities, e.g. Dai
        # Xian), NOT fixed padding. An earlier version of this check
        # required those 2 bytes to be zero too, which incorrectly rejected
        # -- and silently skipped patching -- any city where they weren't.
        pad_ok = all(b == 0 for b in data[name_off + len(city_bytes):name_off + len(city_bytes) + 7])
        if not pad_ok:
            continue

        struct.pack_into("<H", data, rec_start + 11, 32767)       # Population (raw; UI shows raw*100)
        struct.pack_into("<H", data, rec_start + 13, 65535)       # Gold (unsigned display, safe at max)
        struct.pack_into("<I", data, rec_start + 15, 9999999)     # Food
        data[rec_start + 29] = 100                                 # Lnd
        data[rec_start + 30] = 100                                 # Clt
        data[rec_start + 31] = 100                                 # Irr
        data[rec_start + 32] = 100                                 # FlC
        struct.pack_into("<h", data, rec_start + 33, 32767)        # Econ (signed display)
        data[rec_start + 35] = 100                                 # Tax
        data[rec_start + 36] = 100                                 # PS
        struct.pack_into("<h", data, rec_start + 37, 32767)        # Crsb (signed display)
        struct.pack_into("<h", data, rec_start + 39, 32767)        # Crst (signed display)
        struct.pack_into("<h", data, rec_start + 41, 32767)        # Hors (signed display)
        changes += 1
        print(f"  city record patched at 0x{rec_start:x}")

# ---------------------------------------------------------------------------
# 2. RULER SKILLS (soldiers NOT touched for the ruler by default -- use
#    --bump-officers-for-ruler to also max their garrison's troops+stats)
# ---------------------------------------------------------------------------
if ruler_name:
    bump_character(ruler_name, also_max_soldiers=False, label="ruler")

# ---------------------------------------------------------------------------
# 3. --bump-officer NAME (repeatable): max one named officer's skills +
#    their own Soldiers count.
# ---------------------------------------------------------------------------
for name in bump_officers:
    bump_character(name, also_max_soldiers=True, label="officer")

# ---------------------------------------------------------------------------
# 4. --bump-officers-for-ruler NAME (repeatable): max skills + Soldiers for
#    every officer positionally grouped with this ruler (see SCOPE NOTE in
#    the header comment -- this is the ruler's own slot-group/garrison, not
#    necessarily their entire kingdom).
# ---------------------------------------------------------------------------
for name in bump_officers_for_ruler:
    hits = safe_name_hits(name, "ruler (for --bump-officers-for-ruler)")
    if not hits:
        continue
    for name_off in hits:
        rich_stats = name_off - 39
        if not looks_like_stats(rich_stats):
            continue
        for k in range(1, SCAN_WINDOW_SLOTS + 1):
            pos = rich_stats + STRIDE * k
            if not looks_like_stats(pos):
                continue
            for i in range(6):
                data[pos + i] = 100
            changes += 1
            print(f"  officer-for-ruler {name!r} skills maxed at 0x{pos:x}")
            max_soldiers_at(pos, f"officer-for-ruler {name!r}")

if changes == 0:
    print("No changes made -- check that the given names/city match the save exactly.", file=sys.stderr)
    sys.exit(1)

with open(out_path, "wb") as f:
    f.write(data)

print(f"Done. {changes} field group(s) patched. Wrote: {out_path}")
PYEOF
