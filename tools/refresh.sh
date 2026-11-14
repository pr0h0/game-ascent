#!/usr/bin/env bash
# Brings docs, stats, screenshots, videos and the web build up to date.
#
#   tools/refresh.sh <command...> [options]
#
# Commands (several may be given; they run in the order written):
#   tests      every headless test suite, pass/fail summary
#   stats      bot playthroughs of every level on several difficulties -> docs/stats/
#   screens    regenerate docs/screenshots/{levels,ui} (xvfb)
#   gallery    regenerate docs/screenshots/gallery (xvfb)
#   web        Web export into build/web + build/ascent_web.zip
#   linux      Linux export: one self-contained executable, build/linux/Ascent.x86_64
#   macos      macOS export: universal Ascent.app (ad-hoc signed, not notarized) in build/macos/Ascent.zip
#   cutscenes  record the story chapters -> docs/cutscenes/*.mp4 + full_story.mp4   (heavy, runs alone)
#   gameplay   record the bot playing -> docs/gameplay/*.mp4                          (heavy, runs alone)
#   trailer    rough trailer from docs/gameplay + docs/cutscenes -> docs/trailer/trailer.mp4
#   all        tests+stats, screens+gallery and web in parallel, then cutscenes, gameplay, trailer
#   light      like all, without the recordings and the trailer
#
# Options:
#   --levels 1,3        levels for stats/gameplay (default: all; gameplay: 1)
#   --suites smoke,menu test suites to run (default: every suite that quits with its failure count)
#   --difficulties 0,1  difficulties for stats, 0=Recruit .. 3=Nightmare (default: 0,1,2,3)
#   --chapters 0,6      story chapters to record (default: all 0-10)
#   --jobs N            parallel Godot processes for tests/stats (default 4)
#   --speed N           bot time scale for stats (default 4)
#   --fps N             frame rate for gameplay recording (default 60)
#   --display           record on the real display instead of xvfb (faster, opens windows)
#   --gameplay-shots    screens also re-takes docs/screenshots/gameplay (GPU playthroughs, slow)
#   --import            run `godot --headless --import` first (after adding new assets)
#   --dry-run           print what would run, do nothing
#
# Logs: docs/stats/logs/<command>/. Scratch: $REFRESH_TMP (default .refresh_tmp/ in the project).
set -u -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GODOT="${GODOT:-godot}"
WORK="${REFRESH_TMP:-$ROOT/.refresh_tmp}"
LOGS="$ROOT/docs/stats/logs"
JOBS=4; SPEED=4; FPS=60
LEVELS="all"; DIFFS="0,1,2,3"; CHAPTERS="0,1,2,3,4,5,6,7,8,9,10"
SUITES=""; DRY=0; USE_DISPLAY=0; GAMEPLAY_SHOTS=0; DO_IMPORT=0
SUMMARY="$WORK/summary.txt"
CHAPTER_SLUGS=(01_first_shift 02_the_vein 03_black_shaft 04_smelter_row 05_hollow_reach 06_deep_cut 07_overseers_pit 08_glass_seam 09_last_light 10_core_zero 11_ascent_ending)
LEVEL_IDS=(first_shift the_vein black_shaft smelter_row hollow_reach deep_cut overseer_pit glass_seam last_light core_zero)
LEVEL_SLUGS=(first_shift the_vein black_shaft smelter_row hollow_reach deep_cut overseers_pit glass_seam last_light core_zero)
DIFF_NAMES=(Recruit Pilot Veteran Nightmare)
# Suites that render, record or measure rather than pass/fail.
TEST_SKIP=" autoplay render_story shots feature_shots gallery_shots loadout_shots concept_shots concept_shots_v2 cockpit_variants stage_preview fx_perf escape_perf "

cmds=()
while [ $# -gt 0 ]; do
	case "$1" in
		--levels) LEVELS="$2"; shift ;;
		--suites) SUITES="$2"; shift ;;
		--difficulties) DIFFS="$2"; shift ;;
		--chapters) CHAPTERS="$2"; shift ;;
		--jobs) JOBS="$2"; shift ;;
		--speed) SPEED="$2"; shift ;;
		--fps) FPS="$2"; shift ;;
		--display) USE_DISPLAY=1 ;;
		--gameplay-shots) GAMEPLAY_SHOTS=1 ;;
		--import) DO_IMPORT=1 ;;
		--dry-run|-n) DRY=1 ;;
		-h|--help) sed -n '2,33p' "$0" | grep '^#'; exit 0 ;;
		-*) echo "unknown option $1" >&2; exit 2 ;;
		*) cmds+=("$1") ;;
	esac
	shift
done
[ ${#cmds[@]} -eq 0 ] && { sed -n '2,33p' "$0" | grep '^#'; exit 2; }

mkdir -p "$WORK" "$LOGS"
touch "$WORK/.gdignore"   # keep Godot from importing scratch images and videos
: > "$SUMMARY"

say() { printf '\033[1;36m[refresh]\033[0m %s\n' "$*"; }
note() { echo "$*" >> "$SUMMARY"; say "$*"; }
run() {  # run <log> <cmd...>: logs output, honours --dry-run
	local log="$1"; shift
	if [ $DRY -eq 1 ]; then echo "  would run: $*  > ${log#$ROOT/}"; return 0; fi
	mkdir -p "$(dirname "$log")"
	"$@" > "$log" 2>&1
}
level_list() {
	if [ "$LEVELS" = "all" ]; then seq 1 ${#LEVEL_SLUGS[@]}; else tr ',' '\n' <<< "$LEVELS"; fi
}
# Each parallel Godot gets its own user:// (XDG_DATA_HOME), so saves, settings and
# progress files of one run can't trip up another, and the user's own settings are untouched.
fresh_home() {
	local d="$WORK/home/$1"
	rm -rf "$d"; mkdir -p "$d"; echo "$d"
}
xvfb() {  # xvfb <WxH> <cmd...>
	local size="$1"; shift
	if [ $USE_DISPLAY -eq 1 ] && [ -n "${DISPLAY:-}" ]; then "$@"
	else xvfb-run -a -s "-screen 0 ${size}x24" "$@"; fi
}
pool_wait() {  # keep at most $JOBS background jobs
	while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do wait -n 2>/dev/null || true; done
}
check_idle() {
	local load; load=$(cut -d' ' -f1 /proc/loadavg)
	if awk -v l="$load" -v n="$(nproc)" 'BEGIN{exit !(l > n/2)}'; then
		say "warning: load average is $load; recordings may stutter or take long. Other heavy jobs should be stopped."
	fi
}

# ---------------------------------------------------------------------------- tests
do_tests() {
	local dir="$LOGS/tests"; rm -rf "$dir"; mkdir -p "$dir"
	local suites=()
	for scene in tests/*.tscn; do
		local name; name=$(basename "$scene" .tscn)
		[[ "$TEST_SKIP" == *" $name "* ]] && continue
		grep -q 'quit(failures)' "tests/$name.gd" 2>/dev/null || continue
		[ -n "$SUITES" ] && [[ ",$SUITES," != *",$name,"* ]] && continue
		suites+=("$name")
	done
	say "tests: ${suites[*]}"
	for name in "${suites[@]}"; do
		pool_wait
		(
			start=$(date +%s)
			if [ $DRY -eq 1 ]; then run "$dir/$name.log" "$GODOT" --headless --path . "res://tests/$name.tscn"; exit 0; fi
			XDG_DATA_HOME="$(fresh_home "test_$name")" timeout 1200 "$GODOT" --headless --path . "res://tests/$name.tscn" > "$dir/$name.log" 2>&1
			echo "$? $(( $(date +%s) - start ))" > "$dir/$name.rc"
		) &
	done
	wait
	[ $DRY -eq 1 ] && return 0
	local pass=0 fail=0 lines=""
	for name in "${suites[@]}"; do
		read -r rc secs < "$dir/$name.rc"
		local errs; errs=$(grep -c "SCRIPT ERROR" "$dir/$name.log")
		local status="PASS"
		if [ "$rc" = 124 ]; then status="TIMEOUT"; elif [ "$rc" != 0 ]; then status="FAIL($rc)"; fi
		[ "$status" = PASS ] && pass=$((pass+1)) || fail=$((fail+1))
		lines+=$(printf '  %-12s %-9s %4ss  script errors: %s' "$name" "$status" "$secs" "$errs")$'\n'
	done
	note "tests: $pass passed, $fail failed (logs: docs/stats/logs/tests/)"
	printf '%s' "$lines" | tee -a "$SUMMARY"
	[ $fail -eq 0 ]
}

# ---------------------------------------------------------------------------- stats
do_stats() {
	local dir="$LOGS/stats" out="$WORK/stats"; rm -rf "$dir" "$out"; mkdir -p "$dir" "$out"
	local n=0
	for d in ${DIFFS//,/ }; do
		for l in $(level_list); do
			pool_wait
			n=$((n+1))
			local tag="d${d}_l$(printf %02d "$l")"
			local cmd=("$GODOT" --headless --path . res://tests/autoplay.tscn -- "levels=$l" "difficulty=$d" "speed=$SPEED" "report=$out/$tag.json")
			if [ $DRY -eq 1 ]; then run "$dir/$tag.log" "${cmd[@]}"; continue; fi
			( XDG_DATA_HOME="$(fresh_home "stats_$tag")" timeout 2400 "${cmd[@]}" > "$dir/$tag.log" 2>&1; echo $? > "$dir/$tag.rc" ) &
		done
	done
	wait
	[ $DRY -eq 1 ] && return 0
	python3 - "$out" "$ROOT/docs/stats" "$dir" "$SPEED" <<'PY' | tee -a "$SUMMARY"
import json, sys, os, glob, datetime
out, docs, logdir, speed = sys.argv[1:5]
NAMES = ["Recruit", "Pilot", "Veteran", "Nightmare"]
now = datetime.datetime.now()
stamp = now.strftime("%Y-%m-%d %H:%M")
latest_path = os.path.join(docs, "latest.json")
prev = {}
if os.path.exists(latest_path):
    try:
        prev = json.load(open(latest_path))
    except Exception:
        prev = {}
def key(r): return "%d/%d" % (r["difficulty"], r["level"])
prev_runs = {key(r): r for r in prev.get("runs", [])}
new_runs, broken = [], []
for f in sorted(glob.glob(os.path.join(out, "*.json"))):
    try:
        data = json.load(open(f))
    except Exception:
        broken.append(os.path.basename(f)); continue
    for e in data:
        missed = e.get("pickups_missed", [])
        new_runs.append({
            "level": e["level"], "name": e["name"], "difficulty": e.get("difficulty", 1),
            "won": e["won"], "seconds": e["seconds"], "deaths": e["deaths"],
            "damage_taken": e.get("damage_taken"), "kills": e["kills"], "robots": e["robots"],
            "energy_used": e.get("energy_used"), "ammo_used": e.get("ammo_used"),
            "pickups_total": e.get("pickups_total"), "pickups_missed": len(missed), "missed_kinds": missed,
            "secrets": e["secrets"], "astronauts": e["astronauts"], "rank": e["rank"], "score": e["score"],
            "death_spots": e.get("death_spots", []), "stuck": e["stuck"], "teleports": e["teleports"],
            "weapons": e["weapons"], "missiles": e["missiles"], "fps_avg": e["fps_avg"], "escape_left": e["escape_left"],
            "date": stamp,
        })
for tag in sorted(os.path.basename(p)[:-3] for p in glob.glob(os.path.join(logdir, "*.rc"))):
    if not os.path.exists(os.path.join(out, tag + ".json")):
        broken.append(tag)
# Merge: a partial run (one level, one difficulty) replaces only its own rows.
merged = dict(prev_runs)
for r in new_runs:
    merged[key(r)] = r
runs = sorted(merged.values(), key=lambda r: (r["difficulty"], r["level"]))
latest = {"updated": stamp, "speed": float(speed), "runs": runs}
os.makedirs(os.path.join(docs, "history"), exist_ok=True)
json.dump(latest, open(latest_path, "w"), indent=1)
json.dump({"date": stamp, "runs": new_runs}, open(os.path.join(docs, "history", now.strftime("%Y-%m-%d") + ".json"), "w"), indent=1)

def delta(r, field, fmt="{:+g}"):
    p = prev_runs.get(key(r))
    v = r.get(field)
    if v is None: return "-"
    s = ("%g" % round(v, 1)) if isinstance(v, (int, float)) else str(v)
    if p is None or p.get(field) is None or not isinstance(v, (int, float)) or p is r: return s
    d = round(v - p[field], 1)
    return s if d == 0 else "%s (%s)" % (s, fmt.format(d))
def rank(r):
    p = prev_runs.get(key(r))
    return r["rank"] if not p or p["rank"] == r["rank"] or p is r else "%s (was %s)" % (r["rank"], p["rank"])
fresh = {key(r) for r in new_runs}
md = ["# Bot playthrough stats", "",
      "Written by `tools/refresh.sh stats`: the autopilot (`tests/autoplay.tscn`) flies every level headless at %gx speed, carrying the upgrades of earlier levels. "
      "Numbers in brackets are the change since the previous run. Rows marked * were not re-run this time." % float(speed), "",
      "Last update: %s. History: `history/`, raw data: `latest.json`." % stamp, ""]
for d in sorted({r["difficulty"] for r in runs}):
    rows = [r for r in runs if r["difficulty"] == d]
    md += ["## %s (difficulty %d)" % (NAMES[d] if d < len(NAMES) else d, d), "",
           "| Level | Won | Time (s) | Deaths | Damage taken | Kills | Energy used | Missiles used | Pickups missed | Secrets | Rank |",
           "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        mark = "" if key(r) in fresh else " *"
        md.append("| %d %s%s | %s | %s | %s | %s | %s/%d | %s | %s | %s/%s | %s | %s |" % (
            r["level"], r["name"], mark, "yes" if r["won"] else "**NO**", delta(r, "seconds"), delta(r, "deaths"),
            delta(r, "damage_taken"), delta(r, "kills"), r["robots"], delta(r, "energy_used"), delta(r, "ammo_used"),
            delta(r, "pickups_missed"), r.get("pickups_total", "-"), r["secrets"], rank(r)))
    spots = [(r, s) for r in rows for s in r.get("death_spots", [])]
    if spots:
        md += ["", "Deaths:", ""]
        for r, s in spots:
            md.append("- L%d %s, %.0f s: killed by %s at %s while going to %s" % (r["level"], r["name"], s["t"], s["by"] or "?", s["pos"], s["goal"]))
    md.append("")
if broken:
    md += ["## Runs that produced no report", ""] + ["- %s (see `logs/stats/%s.log`)" % (b, b) for b in broken] + [""]
open(os.path.join(docs, "README.md"), "w").write("\n".join(md))
won = sum(1 for r in new_runs if r["won"])
print("stats: %d runs, %d won, %d deaths, %d without report -> docs/stats/README.md" % (len(new_runs), won, sum(r["deaths"] for r in new_runs), len(broken)))
for r in new_runs:
    print("  d%d L%-2d %-16s won=%-5s %s  deaths=%s  damage=%s  kills=%d/%d  missed=%s  rank=%s" % (
        r["difficulty"], r["level"], r["name"], r["won"], delta(r, "seconds") + "s", delta(r, "deaths"),
        delta(r, "damage_taken"), r["kills"], r["robots"], delta(r, "pickups_missed"), rank(r)))
PY
}

# ---------------------------------------------------------------------------- screens
SHOT_RES=2560x1440
shot_godot() {  # shot_godot <log> <scene> <args...>
	local log="$1" scene="$2"; shift 2
	if [ $DRY -eq 1 ]; then run "$log" xvfb $SHOT_RES "$GODOT" --path . --resolution $SHOT_RES "$scene" -- "$@"; return; fi
	XDG_DATA_HOME="$(fresh_home shots)" timeout 1800 bash -c "$(declare -f xvfb); USE_DISPLAY=$USE_DISPLAY; xvfb $SHOT_RES \"\$@\"" _ \
		"$GODOT" --path . --resolution $SHOT_RES "$scene" -- "$@" > "$log" 2>&1
}
count_new() { find "$1" -name '*.png' -newer "$WORK/.mark_$2" | wc -l; }
do_screens() {
	local dir="$LOGS/screens"; rm -rf "$dir"; mkdir -p "$dir"
	local L=docs/screenshots/levels U=docs/screenshots/ui G=docs/screenshots/gameplay
	mkdir -p $L $U $G; touch "$WORK/.mark_screens"
	local failed=()
	shot_godot "$dir/shots.log" res://tests/shots.tscn "$ROOT/$L" || failed+=(shots)
	# Every generated level: its map from above and the side, and a tour of its rooms.
	mkdir -p docs/level_maps
	for i in "${!LEVEL_IDS[@]}"; do
		local id="${LEVEL_IDS[$i]}"
		run "$dir/map_$id.log" python3 tools/maze_preview.py "$id" "$ROOT/docs/level_maps/$(printf %02d $((i+1)))_$id.png" || failed+=(map_$id)
		mkdir -p "$L/$id"; [ $DRY -eq 1 ] || rm -f "$L/$id"/*.png
		shot_godot "$dir/tour_$id.log" res://tests/level_tour.tscn "$ROOT/$L/$id" "$i" 14 || failed+=(tour_$id)
	done
	shot_godot "$dir/feature_shots.log" res://tests/feature_shots.tscn "$ROOT/$U" || failed+=(feature_shots)
	shot_godot "$dir/menu.log" res://tests/menu.tscn "$ROOT/$U" || failed+=(menu)
	shot_godot "$dir/controls.log" res://tests/controls.tscn "$ROOT/$U" || failed+=(controls)
	shot_godot "$dir/tuner.log" res://tests/tuner.tscn "$ROOT/$U" || failed+=(tuner)
	if [ $GAMEPLAY_SHOTS -eq 1 ]; then
		shot_godot "$dir/gameplay.log" res://tests/autoplay.tscn "levels=2,4,6,8,10" "shots=$ROOT/$G" || failed+=(gameplay)
	fi
	[ $DRY -eq 1 ] && return 0
	note "screens: $(count_new docs/screenshots screens) images updated in docs/screenshots; failed: ${failed[*]:-none} (logs: docs/stats/logs/screens/)"
	[ ${#failed[@]} -eq 0 ]
}

do_gallery() {
	local dir="$LOGS/gallery"; rm -rf "$dir"; mkdir -p "$dir" docs/screenshots/gallery
	touch "$WORK/.mark_gallery"
	shot_godot "$dir/gallery_shots.log" res://tests/gallery_shots.tscn "$ROOT/docs/screenshots/gallery"
	local rc=$?
	[ $DRY -eq 1 ] && return 0
	note "gallery: $(count_new docs/screenshots/gallery gallery) models shot, exit $rc$(grep -c 'no model for' "$dir/gallery_shots.log" | sed 's/^/, missing models: /')"
	return $rc
}

# ---------------------------------------------------------------------------- web
do_web() {
	local dir="$LOGS/web"; mkdir -p "$dir"
	local build="$ROOT/build/web"
	if [ $DRY -eq 1 ]; then run "$dir/export.log" "$GODOT" --headless --path . --export-release Web "$build/index.html"; return 0; fi
	rm -rf "$build"; mkdir -p "$build"
	touch "$ROOT/build/.gdignore"   # keep Godot from importing the build output
	timeout 1800 "$GODOT" --headless --path . --export-release Web "$build/index.html" > "$dir/export.log" 2>&1
	local rc=$?
	if [ ! -s "$build/index.html" ]; then note "web: export FAILED (exit $rc, see docs/stats/logs/web/export.log)"; return 1; fi
	# Browsers cache index.pck by name and keep running the old game after an update, so
	# the pack (and the splash and loader) get a per-build name the page asks for instead.
	local h; h=$(sha1sum "$build/index.pck" | cut -c1-10)
	mv "$build/index.pck" "$build/index.$h.pck"
	sed -i -e "s/\"executable\":\"index\"/\"executable\":\"index\",\"mainPack\":\"index.$h.pck\"/" \
		-e "s/\"index.pck\":/\"index.$h.pck\":/" -e "s/src=\"index.png\"/src=\"index.png?v=$h\"/" \
		-e "s/src=\"index.js\"/src=\"index.js?v=$h\"/" "$build/index.html"
	grep -q "index.$h.pck" "$build/index.html" || { note "web: could not point index.html at index.$h.pck"; return 1; }
	rm -f "$ROOT/build/ascent_web.zip"
	(cd "$build" && zip -qr9 "$ROOT/build/ascent_web.zip" .)
	note "web: build/web $(du -sh "$build" | cut -f1), zip $(du -h "$ROOT/build/ascent_web.zip" | cut -f1) (pck $(du -h "$build"/*.pck 2>/dev/null | cut -f1 | head -1))"
}

do_linux() {
	local dir="$LOGS/linux" out="$ROOT/build/linux/Ascent.x86_64"; mkdir -p "$dir"
	if [ $DRY -eq 1 ]; then run "$dir/export.log" "$GODOT" --headless --path . --export-release Linux "$out"; return 0; fi
	rm -rf "$ROOT/build/linux"; mkdir -p "$ROOT/build/linux"
	touch "$ROOT/build/.gdignore"
	timeout 1800 "$GODOT" --headless --path . --export-release Linux "$out" > "$dir/export.log" 2>&1
	local rc=$?
	if [ ! -x "$out" ]; then note "linux: export FAILED (exit $rc, see docs/stats/logs/linux/export.log)"; return 1; fi
	note "linux: build/linux/Ascent.x86_64 $(du -h "$out" | cut -f1)"
}

do_macos() {
	local dir="$LOGS/macos" out="$ROOT/build/macos/Ascent.zip"; mkdir -p "$dir"
	if [ $DRY -eq 1 ]; then run "$dir/export.log" "$GODOT" --headless --path . --export-release macOS "$out"; return 0; fi
	rm -rf "$ROOT/build/macos"; mkdir -p "$ROOT/build/macos"
	touch "$ROOT/build/.gdignore"
	timeout 1800 "$GODOT" --headless --path . --export-release macOS "$out" > "$dir/export.log" 2>&1
	local rc=$?
	if [ ! -s "$out" ]; then note "macos: export FAILED (exit $rc, see docs/stats/logs/macos/export.log)"; return 1; fi
	note "macos: build/macos/Ascent.zip $(du -h "$out" | cut -f1)"
}

# ---------------------------------------------------------------------------- recordings
OVERRIDE="$ROOT/override.cfg"
override_on() {
	if [ -e "$OVERRIDE" ] && ! grep -q 'refresh.sh' "$OVERRIDE"; then
		say "override.cfg exists and is not ours; refusing to overwrite it"; return 1
	fi
	printf '; written by tools/refresh.sh for Movie Maker, removed afterwards\n[display]\n\nwindow/size/window_width_override=1920\nwindow/size/window_height_override=1080\n' > "$OVERRIDE"
}
override_off() { grep -qs 'refresh.sh' "$OVERRIDE" && rm -f "$OVERRIDE"; return 0; }
trap override_off EXIT
trap 'override_off; exit 130' INT TERM

movie() {  # movie <log> <avi> <fps> <scene> <args...>
	local log="$1" avi="$2" fps="$3" scene="$4"; shift 4
	if [ $DRY -eq 1 ]; then run "$log" xvfb 1920x1080 "$GODOT" --path . --write-movie "$avi" --fixed-fps "$fps" "$scene" -- "$@"; return; fi
	XDG_DATA_HOME="$(fresh_home movie)" timeout 3600 bash -c "$(declare -f xvfb); USE_DISPLAY=$USE_DISPLAY; xvfb 1920x1080 \"\$@\"" _ \
		"$GODOT" --path . --write-movie "$avi" --fixed-fps "$fps" "$scene" -- "$@" > "$log" 2>&1
}
to_mp4() {  # to_mp4 <avi> <mp4>
	[ $DRY -eq 1 ] && { echo "  would encode $1 -> ${2#$ROOT/}"; return 0; }
	ffmpeg -y -hide_banner -loglevel error -i "$1" -c:v libx264 -crf 19 -preset medium -pix_fmt yuv420p \
		-c:a aac -b:a 192k -movflags +faststart "$2.part.mp4" && mv "$2.part.mp4" "$2" && rm -f "$1"
}
duration() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null; }

do_cutscenes() {
	check_idle
	local dir="$LOGS/cutscenes" tmp="$WORK/cutscenes"; mkdir -p "$dir" "$tmp" docs/cutscenes
	[ $DRY -eq 1 ] || override_on || return 1
	local ok=0 bad=()
	for i in ${CHAPTERS//,/ }; do
		local slug=${CHAPTER_SLUGS[$i]}
		say "cutscene $slug"
		movie "$dir/$slug.log" "$tmp/$slug.avi" 30 res://tests/render_story.tscn "$i"
		if [ $DRY -eq 0 ] && grep -qE "SCRIPT ERROR|Parse Error" "$dir/$slug.log"; then say "  script errors in $slug, see log"; fi
		if to_mp4 "$tmp/$slug.avi" "$ROOT/docs/cutscenes/$slug.mp4"; then ok=$((ok+1)); else bad+=("$slug"); fi
	done
	override_off
	[ $DRY -eq 1 ] && return 0
	# full_story.mp4: every chapter in order (all were encoded with the same settings).
	local list="$tmp/concat.txt"; : > "$list"
	for slug in "${CHAPTER_SLUGS[@]}"; do
		[ -s "docs/cutscenes/$slug.mp4" ] && echo "file '$ROOT/docs/cutscenes/$slug.mp4'" >> "$list"
	done
	ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$list" -c copy -movflags +faststart docs/cutscenes/full_story.part.mp4 \
		&& mv docs/cutscenes/full_story.part.mp4 docs/cutscenes/full_story.mp4
	note "cutscenes: $ok recorded, failed: ${bad[*]:-none}; full_story.mp4 $(printf '%.0f' "$(duration docs/cutscenes/full_story.mp4)") s"
	[ ${#bad[@]} -eq 0 ]
}

do_gameplay() {
	check_idle
	local dir="$LOGS/gameplay" tmp="$WORK/gameplay"; mkdir -p "$dir" "$tmp" docs/gameplay
	[ $DRY -eq 1 ] || override_on || return 1
	local made=() bad=()
	local lv=1; [ "$LEVELS" != "all" ] && lv="$LEVELS"   # default: level 1 only
	for l in ${lv//,/ }; do
		local name="level${l}_${LEVEL_SLUGS[$((l-1))]}"
		say "gameplay $name"
		movie "$dir/$name.log" "$tmp/$name.avi" "$FPS" res://tests/autoplay.tscn "levels=$l" audio=1
		if to_mp4 "$tmp/$name.avi" "$ROOT/docs/gameplay/$name.mp4"; then made+=("$name"); else bad+=("$name"); fi
	done
	override_off
	[ $DRY -eq 1 ] && return 0
	note "gameplay: recorded ${made[*]:-nothing}; failed: ${bad[*]:-none}"
	[ ${#bad[@]} -eq 0 ]
}

# ---------------------------------------------------------------------------- trailer
FONT="$ROOT/assets/fonts/Orbitron.ttf"
TRAILER_MUSIC="${TRAILER_MUSIC:-$ROOT/assets/music/ascent.ogg}"
seg_n=0
card() {  # card <seconds> <big text> [small text]
	seg_n=$((seg_n+1))
	local f="$WORK/trailer/seg_$(printf %03d $seg_n).mp4" d="$1"
	printf '%s' "$2" > "$WORK/trailer/t${seg_n}a.txt"; printf '%s' "${3:-}" > "$WORK/trailer/t${seg_n}b.txt"
	local fo; fo=$(awk -v d="$d" 'BEGIN{print d-0.5}')
	[ $DRY -eq 1 ] && { echo "  card ${d}s: $2 / ${3:-}"; return; }
	ffmpeg -y -hide_banner -loglevel error -f lavfi -i "color=c=0x05070a:s=1920x1080:r=30:d=$d" -vf \
"drawtext=fontfile=$FONT:textfile=$WORK/trailer/t${seg_n}a.txt:fontcolor=0xffb347:fontsize=120:x=(w-tw)/2:y=(h-th)/2-40,\
drawtext=fontfile=$FONT:textfile=$WORK/trailer/t${seg_n}b.txt:fontcolor=0x9fd8ff:fontsize=44:x=(w-tw)/2:y=h/2+80,\
fade=in:st=0:d=0.5,fade=out:st=$fo:d=0.5,format=yuv420p" \
		-c:v libx264 -crf 18 -preset veryfast -r 30 "$f" && echo "file '$f'" >> "$WORK/trailer/list.txt"
}
clip() {  # clip <video> <start s> <seconds> [caption]
	seg_n=$((seg_n+1))
	local f="$WORK/trailer/seg_$(printf %03d $seg_n).mp4" d="$3"
	local fo; fo=$(awk -v d="$d" 'BEGIN{print d-0.3}')
	local cap=""
	if [ -n "${4:-}" ]; then
		printf '%s' "$4" > "$WORK/trailer/t${seg_n}c.txt"
		cap=",drawtext=fontfile=$FONT:textfile=$WORK/trailer/t${seg_n}c.txt:fontcolor=0xffffff:fontsize=54:x=(w-tw)/2:y=150:box=1:boxcolor=0x000000@0.5:boxborderw=20"
	fi
	[ $DRY -eq 1 ] && { echo "  clip ${1#$ROOT/} @${2}s ${d}s ${4:-}"; return; }
	ffmpeg -y -hide_banner -loglevel error -ss "$2" -t "$d" -i "$1" -an -vf \
"scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,fps=30,fade=in:st=0:d=0.3,fade=out:st=$fo:d=0.3$cap,format=yuv420p" \
		-c:v libx264 -crf 18 -preset veryfast -r 30 "$f" && echo "file '$f'" >> "$WORK/trailer/list.txt"
}
at() { awk -v d="$(duration "$1")" -v f="$2" 'BEGIN{printf "%.2f", d*f}'; }  # time at a fraction of a video

do_trailer() {
	local tmp="$WORK/trailer"; rm -rf "$tmp"; mkdir -p "$tmp" docs/trailer
	: > "$tmp/list.txt"; seg_n=0
	local plays=() cuts=()
	for f in docs/gameplay/*.mp4; do [ -s "$f" ] && plays+=("$ROOT/$f"); done
	for s in "${CHAPTER_SLUGS[@]}"; do [ -s "docs/cutscenes/$s.mp4" ] && cuts+=("$ROOT/docs/cutscenes/$s.mp4"); done
	if [ ${#plays[@]} -eq 0 ] || [ ${#cuts[@]} -eq 0 ]; then note "trailer: needs docs/gameplay/*.mp4 and docs/cutscenes/*.mp4"; return 1; fi
	# Gameplay moments as fractions of a run: entry, first fights, key, reactor, escape, exit.
	# Cutscene moments, varied so neighbouring chapters don't show the same kind of shot.
	local ct_frac=(0.45 0.62 0.30 0.75 0.55 0.35 0.45 0.68 0.25 0.60 0.50)
	local gp_frac=(0.12 0.18 0.35 0.48 0.80 0.90) gp_len=(3.5 3 3 3 4 4)
	gp() { local i=$1; local v=${plays[$(( i % ${#plays[@]} ))]}; clip "$v" "$(at "$v" ${gp_frac[$i]})" ${gp_len[$i]} "${2:-}"; }
	ct() { local i=$1; [ $i -lt ${#cuts[@]} ] || return 0; clip "${cuts[$i]}" "$(at "${cuts[$i]}" ${ct_frac[$i]})" 3 ""; }
	card 3.5 "ASCENT" ""
	ct 0
	card 2.5 "THE MINE WENT DARK" "312 miners unaccounted for"
	gp 0; gp 1 "FLY IN ANY DIRECTION"; gp 2
	ct 1; ct 2; ct 3
	card 2.5 "TEN LEVELS DOWN" ""
	gp 3 "DESTROY THE REACTOR"; ct 4; ct 5; ct 6; ct 7
	card 2.5 "ONE WAY OUT" ""
	gp 4 "60 SECONDS TO ESCAPE"; gp 5
	ct 8; ct 9; ct 10
	card 5 "ASCENT" "a six-degrees-of-freedom mine shooter"
	[ $DRY -eq 1 ] && return 0
	local video="$tmp/video.mp4"
	ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$tmp/list.txt" -c copy "$video" || { note "trailer: concat failed"; return 1; }
	local len; len=$(duration "$video")
	local fo; fo=$(awk -v d="$len" 'BEGIN{print d-3}')
	ffmpeg -y -hide_banner -loglevel error -i "$video" -stream_loop -1 -i "$TRAILER_MUSIC" -map 0:v -map 1:a -t "$len" \
		-af "afade=in:st=0:d=1,afade=out:st=$fo:d=3" -c:v libx264 -crf 21 -preset medium -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart docs/trailer/trailer.part.mp4 \
		&& mv docs/trailer/trailer.part.mp4 docs/trailer/trailer.mp4 || { note "trailer: mux failed"; return 1; }
	note "trailer: docs/trailer/trailer.mp4, $(printf '%.0f' "$len") s from ${#plays[@]} gameplay and ${#cuts[@]} cutscene videos, $(du -h docs/trailer/trailer.mp4 | cut -f1)"
}

# ---------------------------------------------------------------------------- main
do_light() {
	( do_tests; do_stats ) &
	( do_screens; do_gallery ) &
	( do_web; do_linux; do_macos ) &
	wait
}
start=$(date +%s)
if [ $DO_IMPORT -eq 1 ]; then say "importing"; run "$LOGS/import.log" "$GODOT" --headless --path . --import; fi
status=0
for c in "${cmds[@]}"; do
	case "$c" in
		tests|stats|screens|gallery|web|linux|macos|cutscenes|gameplay|trailer) say "== $c"; "do_$c" || status=1 ;;
		light) say "== light (parallel)"; do_light ;;
		all) say "== all: light jobs in parallel, then recordings alone"; do_light; do_cutscenes || status=1; do_gameplay || status=1; do_trailer || status=1 ;;
		*) echo "unknown command $c" >&2; status=2 ;;
	esac
done
echo
say "summary ($(( $(date +%s) - start )) s)"
cat "$SUMMARY"
exit $status
