# Code review: scripts/*.gd and tools/blender/*.py

Review date: 2026-11-10. This was a read-only pass; no game code was changed. Other agents were editing robot.gd, player.gd, fx.gd, level.gd, mats.gd, escape_run.gd, cutscene.gd, music.gd, sfx.gd and hud.gd at the same time, so line numbers will drift. Search for the quoted snippet to find each spot.

Severity:
- **High**: a player-visible bug or a lasting broken state.
- **Medium**: a bug in an edge case, or a measurable performance cost.
- **Low**: polish, small waste or dead code.

## Top 10 (fix first)

| # | Sev | Where | Problem |
| --- | --- | --- | --- |
| 1 | High | sfx.gd `_release` / `finished.connect` | The voice counter leaks when a level frees a playing sound, so sounds go silent for the rest of the session |
| 2 | High | missile.gd, flare.gd, singularity.gd, mine.gd launch | Launch sounds play at the world origin, or not at all |
| 3 | Medium | game.gd escape bonus | An extra life crossed by the escape bonus is lost |
| 4 | Medium | player.gd `release_rail` | A rail charge fires while disrupted or out of energy, and carries over through death |
| 5 | Medium | robot.gd `_on_player_died` | One death wakes every robot in the mine and queues A* for each |
| 6 | Medium | robot.gd cinder detonation, hive brood | The player is credited with kills they did not make, and brood can be farmed for score |
| 7 | Medium | progress.gd `cfg.load(path)` unchecked | A corrupt file wipes all progress on the next save |
| 8 | Medium | bolt.gd, player.gd muzzle, fx.gd sparks, missile.gd | Per-shot lights, particle resources, timers and tweens (allocation churn) |
| 9 | Medium | hud.gd, sentry.gd, robot.gd warden | Raycasts and group scans every frame |
| 10 | Medium | pause_menu.gd with automap / settings_panel.gd gamepad page | Pause and resume leave overlays open while the game runs underneath |

---

## High

### H1. Sound voices leak, so sounds go permanently silent
`scripts/sfx.gd` (`_release`, around lines 38/58/70)
```gdscript
p3.finished.connect(_release.bind(sound, p3))
```
`_voices[sound]` only goes down on `finished`. Positional players are children of `Game.level`, so a restart, level change or the cutscene `_clear_set()` (cutscene.gd points `Game.level` at `_set`) frees them mid-play and `finished` never fires. After 8 leaks (`MAX_VOICES`) that sound, for example `explode_boss`, never plays again until the game restarts.
**Fix:** release on `tree_exiting` instead, which fires on both a normal end and a free:
```gdscript
p3.tree_exiting.connect(_release.bind(sound, p3))
p3.finished.connect(p3.queue_free)
```

### H2. Launch sounds play at the world origin
`scripts/missile.gd:30-31` and `:63`. The same pattern is in `flare.gd` (~74), `singularity.gd` (~50) and `mine.gd` (~59).
```gdscript
Game.level.add_child(m)
m.global_position = at
...
Sfx.play({"cluster": "missile_cluster", ...}.get(kind, "missile"), global_position, ...)
```
`_ready()` runs inside `add_child`, before the position is set. Every missile (the player's and robots'), flare, singularity and mine launch sound comes from (0,0,0). It is dropped entirely when the player is further than `MAX_HEARD_DISTANCE` from the origin.
**Fix:** set `m.position = at` before `add_child` (the level sits at the origin), or play the sound from `launch()` after positioning.

## Medium

### M1. The escape bonus can swallow an extra life
`scripts/game.gd:393-398`
```gdscript
finished = true
...
score += escape_bonus
```
The `score` setter calls `_award_extra_lives()`, which moves `_life_mark` forward but grants nothing because of `and not finished`. Crossing a 30,000-point mark with the bonus loses that life.
**Fix:** add the bonus before `finished = true`, or move the mark only when the life is actually granted.

### M2. A rail charge ignores disruption, energy and death
`scripts/player.gd` (`release_rail`, ~475; trigger logic ~458)
```gdscript
elif rail_charge > 0.0 and not pressed: release_rail()
...
energy -= float(w["energy"])
```
Releasing fires even when a pulse mine disrupted you or the afterburner emptied your energy, and energy can go negative. `_respawn` never resets `rail_charge`, so a charge held at death fires on the first frame after respawn.
**Fix:** in `release_rail`, cancel (charge = 0) if `_disrupted` or `energy < w["energy"]`. Reset `rail_charge` and `_rail_sound_on` in `_die`/`_respawn`.

### M3. A player death wakes the whole mine
`scripts/robot.gd` (`_on_player_died`, ~157)
```gdscript
_returning = true
_needs_home_path = true
```
This runs for every robot, including dormant ones still at home. `_dormant()` is false while `_returning`, so every far robot goes back to full physics, and each queues an A* search (throttled to one per 3 frames, about 300 frames for core_zero's 98 robots).
**Fix:** only do it `if alerted or global_position.distance_to(home) > 2.0`.

### M4. Kills and score the player didn't earn
`scripts/robot.gd` (cinder ~326, hive ~434)
```gdscript
Weapons.splash_player(...)
_die()
...
_brood.append(Game.level.spawn_robot("tick", ..., true))
```
A cinder that blows itself up on the player goes through `_die()`, which calls `Game.add_kill(cfg["score"])` and may drop a pickup. Hive brood refills every 7 s, and every tick gives 100 points plus a kill count, so it can be farmed indefinitely (and it skews kill stats).
**Fix:** `_die(credit := true)`, called with false on self-detonation. Give spawned brood no score and no drops.

### M5. A corrupt progress file wipes all progress
`scripts/progress.gd:14,26,35,45,54,61`
```gdscript
var cfg := ConfigFile.new()
cfg.load(path)
```
If the parse fails, `cfg` is empty and the next `save()` overwrites every `best_*` and `finished_game`.
**Fix:** `var err := cfg.load(path); if err != OK and err != ERR_FILE_NOT_FOUND: push_error(...); return`. Better still, load once and cache.

### M6. A save with a bad difficulty crashes the load
`scripts/saves.gd:68-71`
```gdscript
for field in ["id", "created_unix", "level_index", "score", "lives", ...]:
```
`difficulty` is never range-checked and field types aren't checked, so `DIFFICULTIES[difficulty]` indexes out of range in `Game.diff()`, LevelCard and ResultsScreen.
**Fix:** reject saves where `difficulty` is outside `0..DIFFICULTIES.size()-1` or any field isn't a number.

### M7. Pause on top of the automap resumes into a running game behind the map
`scripts/pause_menu.gd:58-63` and `scripts/automap.gd:~270`
```gdscript
if not (event.is_action_pressed("pause_game") or (visible and event.is_action_pressed("ui_cancel"))):
```
Gamepad Start (`pause_game`) isn't consumed by the automap. Resume sets `paused = false` while the map is still open, with the mouse captured.
**Fix:** ignore input in the pause menu while `Game.level.automap.is_open`, or have the automap close itself on `pause_game`.

### M8. The gamepad page outlives the pause menu
`scripts/settings_panel.gd:65-70`
```gdscript
var layer := CanvasLayer.new()
layer.layer = 90
add_child(layer)
```
A CanvasLayer doesn't inherit visibility from its parent Control. Pressing Start while the gamepad page is open hides SettingsPanel, but the full-screen page (97% opaque) stays, and a second Start unpauses the game behind it.
**Fix:** close `_gamepad_page` on `visibility_changed`, or bind `layer.visible` to `is_visible_in_tree()`.

### M9. Slider drags rewrite settings and re-apply the window many times a second
`scripts/settings_panel.gd:141-143`
```gdscript
slider.value_changed.connect(func(v: float):
	show_value.call(v)
	Settings.change(key, v))
```
`Settings.change` runs `apply()` (window mode, vsync, viewport), `save_settings()` (a disk write) and emits `settings_changed` to the level, player and reactor, once per tick.
**Fix:** apply volume-type values live, and save on `drag_ended` or with a debounced Timer of about 0.3 s.

### M10. Per-shot lights and tweens
`scripts/bolt.gd:~59` and `scripts/player.gd` (`_muzzle_flash`, ~541)
```gdscript
var light := OmniLight3D.new()
```
Lasers fire about 9 shots/s (18 with dual fire), the reactor nova 12 bolts at once and the boss fan 7. That is dozens of short-lived dynamic omni lights, each with its own node and tween.
**Fix:** drop bolt lights (emissive mesh plus glow is enough) or light only every Nth bolt. Use one persistent muzzle light per muzzle and pulse its energy.

### M11. New particle resources per missile
`scripts/missile.gd:43-52`
```gdscript
var pm := ParticleProcessMaterial.new()
```
Each missile also builds its own `Fx._ramp(...)` and `Fx._curve(...)` (a Gradient, GradientTexture1D, Curve and CurveTexture). A swarm fires 8 at once.
**Fix:** cache in a `static var`, as `Fx._process_mat` already does.

### M12. Sparks create particles, a light, a timer and a tween per impact
`scripts/fx.gd` (`sparks` ~207/211, `_particles` ~63)
```gdscript
p.get_tree().create_timer(life + 0.2).timeout.connect(p.queue_free)
```
**Fix:** use `p.finished.connect(p.queue_free)` (GPUParticles3D one_shot emits `finished`). Better, pool a few spark emitters and `restart()` them.

### M13. Physics queries and group scans every frame
- `scripts/hud.gd:~292-297` (and ~205)
  ```gdscript
  for e in get_tree().get_nodes_in_group("enemy"):
  	... or not p.has_line_of_sight(e):
  ```
  The group array is built twice per frame and one ray is cast per visible enemy per frame. `_incoming.filter(...).slice(...)` also allocates even when empty.
  **Fix:** cache line of sight per enemy at about 10 Hz, fetch the group once per frame, and skip the filter when it's empty.
- `scripts/sentry.gd:~75`
  ```gdscript
  _active = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
  ```
  This runs every physics frame within 150 m. **Fix:** throttle to 0.1-0.15 s, as `Robot._think` does.
- `scripts/robot.gd` (`_heal_allies`, ~447)
  ```gdscript
  for other in get_tree().get_nodes_in_group("enemy"):
  ```
  This runs every frame while a warden has line of sight. **Fix:** run it on the think tick and scale healing by elapsed time.

### M14. Cockpit screens render while hidden
`scripts/cockpit_mfd.gd:51-61`
```gdscript
func set_active(on: bool) -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = ...
```
`_process` keeps calling `queue_redraw()` at 15 Hz outside cockpit view. The radar walks the `enemy` and `pickup` groups and draws 68 scanlines that nobody sees.
**Fix:** add `set_process(on)` in `set_active`.

## Low

### L1. Robot separation is O(n²)
`robot.gd:~194`: every alerted robot walks the full `enemy` group every 0.14 s, and alarm spawns make it worse. **Fix:** compute one shared position list per frame, or use a spatial query.

### L2. Short-lived projectiles scan groups every frame
`singularity.gd:~71` (`_pull`) and `mine.gd:~138` (`_watch_for_enemies`; player mines live 45 s) both call `get_nodes_in_group("enemy")` every physics frame. **Fix:** throttle to 0.1 s, or use an `Area3D`.

### L3. New ray query object per projectile per frame
`bolt.gd:~76` `PhysicsRayQueryParameters3D.create(from, to, mask)`, and the same in missile, flare and singularity. **Fix:** keep one query per instance and update `.from`/`.to`.

### L4. Ammo pickups are consumed when full
`pickup.gd:~111`
```gdscript
p.missiles = mini(MAX_MISSILES, p.missiles + AMMO_BOOST)
```
There is no "already full" early return (shield and energy have one), so at the cap the pickup vanishes and still shows "+3". The `ammo_*` branch has the same problem. **Fix:** `return` before collecting when at the cap.

### L5. A robot's rail charge freezes when line of sight breaks
`robot.gd:~336`: `update_rail_charge` only runs from `_attack`, so a longshot keeps a partial charge and fires instantly when it next sees you. **Fix:** clear `_rail_charge` when line of sight is lost or the robot is stunned.

### L6. The robot saw sound never stops
`robot.gd:~381`
```gdscript
_saw = Sfx.positional_loop("robot_saw", self, ...)
```
It is created on the first melee and never stopped, so it keeps whining while the robot returns home. **Fix:** stop it when the robot is no longer alerted or has no line of sight.

### L7. The singularity pulls robots through walls
`singularity.gd:~88`: `e.global_position += ...` bypasses collision. **Fix:** add to `e.velocity` instead.

### L8. Doors process forever
`door.gd:~71`: `_process` returns early for open, hidden and entry doors but still runs. **Fix:** `set_process(false)` in `_open()` and in `_ready` for hidden/entry doors.

### L9. Alarm lights freeze mid-pulse out of range
`level.gd:~302`: lights outside `ALARM_RANGE` are skipped and keep whatever value they last had. **Fix:** set a fixed alarm level once when a light leaves range.

### L10. The quad cache key doesn't match the stored size
`fx.gd:~68/73`: the key is `snappedf(size, 0.5)`, but `q.size = Vector2.ONE * size` stores the first caller's unsnapped size, so tiny sizes share one key with whatever size came first. **Fix:** build the quad with the snapped size.

### L11. New shockwave material per explosion
`fx.gd:~163` `var mat := StandardMaterial3D.new()`. **Fix:** use a cached shader with an instance uniform for alpha.

### L12. Escape fire is built when the escape triggers
`escape_run.gd:~173-185`: the FastNoiseLite, the 256² NoiseTexture2D and the shader compile happen at the trigger moment, causing a hitch. **Fix:** prebuild them in `setup()` or `Level._warm_up()`.

### L13. The boss death sequence duplicates the reactor's
`boss.gd:~107-120` duplicates `reactor.gd:~123-129` (explosions, `on_reactor_destroyed`, alarm, escape music). **Fix:** move it into one shared `Game.trigger_core_failure(at)`.

### L14. Small redundant work
- `weapons.gd:~114`: the arc re-fetches `_hostiles()` on every jump. Fetch it once.
- `player.gd:~270`: `_weapon_key(event)` is evaluated twice per event.

### L15. Changing any setting turns fog and SSAO back on during the space cutaway
`level.gd:72-74`
```gdscript
_env.ssao_enabled = Settings.uses_ssao()
```
**Fix:** keep an `_in_space` flag and skip these lines while it is set.

### L16. The gamepad diagram redraws every frame and allocates style boxes
`gamepad_diagram.gd:42-44` and `:113`: `queue_redraw()` runs every frame while a pad is connected, each draw makes about 12 `StyleBoxFlat.new()`, and `connected_pad()` is called dozens of times. **Fix:** cache the boxes, read the pad once, and redraw only when its state changes.

### L17. Menus re-scan every save file per panel switch
`main_menu.gd:~205/223/272`: `Saves.has_any()`, `Progress.unlocked_level()` and 40 `Progress.best()` file loads run on each switch. **Fix:** cache `Saves.list()` and invalidate it in `write()`/`delete()`.

### L18. A malformed controls file can crash startup
`controls.gd:247-248`
```gdscript
if saved is Array and saved.size() == int(SLOTS[device]):
```
The elements aren't checked to be strings. **Fix:** also require `saved.all(func(c): return c is String)`.

### L19. Rebinding edge cases
- `bind_rows.gd:77-99`: clicking another slot while one is listening binds Left mouse, which silently swaps it away from Fire.
- `controls.gd:~180`: the logical-keycode fallback is later rebuilt as a physical keycode, so the binding may not match the key pressed.

### L20. Pause Resume captures the mouse even on autopilot
`pause_menu.gd:~43` sets `Input.mouse_mode = Input.MOUSE_MODE_CAPTURED` unconditionally. **Fix:** `if not Game.autopilot:`, as `automap.gd` does.

### L21. Cutscene robustness
- `cutscene.gd:~827-836`: it checks only `_door_upper` before using `_door_lower`. Check both.
- `cutscene.gd:~440`: `chapter["shots"].find(shot)` searches by value equality, so duplicate shots resolve to the wrong voice files. Pass `shot_index` instead.

### L22. Music volume is written every frame
`music.gd:124-128`: `get_bus_index(&"Music")`, a string lookup and `set_bus_volume_db` run every frame, which also fights `Settings._set_volume`. **Fix:** cache the index and write only on change.

### L23. Duplicated constants that can drift
- `hud.gd:~228` and `cockpit_mfd.gd:~94`: `p.shield < 30.0` duplicates `Player.LOW_SHIELD`.
- `player.gd:16/23`: `FIRE_INTERVAL` and `ENERGY_PER_SHOT` are used only by gallery_data.gd; gameplay uses `Weapons.PRIMARY`.
- `pickup.gd:7`: `MAX_MISSILES := 12` duplicates `Weapons.SECONDARY["homing"]["cap"]`.

### L24. Dead code
- `player.gd:~202`: `func refresh_view()` has no callers.
- `level.gd:14/195`: `var escape_door` is written but never read.
- `hud.gd:18`: `var _center: Label` is unused.
- `gallery_panel.gd:22/68`: `_back` is assigned but never read. Gallery row buttons also skip `MenuStyle.add_sounds`.

## tools/blender

### B1. The alarm sound jumps in pitch mid-sweep (Medium, audible)
`gen_audio.py:~286`
```python
np.sin(2 * np.pi * np.interp(t, [0, 0.6, 1.2], [520, 880, 520]) * t)
```
It multiplies a time-varying frequency by `t` instead of integrating it. The real pitch climbs to about 1240 Hz, then drops straight to 520 Hz at 0.6 s. **Fix:** `np.sin(2*np.pi*np.cumsum(f)/RATE)` (synth.py's `phase_of`).

### B2. A level's .glb and .json can drift apart
`level.py:~474` then `~493`: `export(LEVEL_ID + ".glb")` runs before `seat_on_surface()`, which can raise, leaving a new .glb next to a stale .json. **Fix:** build the data first, then write both.

### B3. Secret-room placement can crash
`level_api.py:~251`: `r.choice(metal_tunnels)` raises `IndexError`, which `_try` doesn't catch, when no tunnel is metal. **Fix:** guard for an empty list.

### B4. Fragile helpers
- `kit.py` `catmull(keys, count)` divides by zero when `count == 1` and raises `IndexError` when `len(keys) < 2`.
- `synth.write_ogg` leaves `.tmp.wav` behind if ffmpeg fails. **Fix:** wrap it in try/finally.
- `gen_textures.write_import` rewrites `.import` files every run, dropping `uid`/`dest_files` and churning UIDs. **Fix:** skip files that already exist.

### B5. Dead code
- Unused imports: `level.py` (`math`, `Vector`, `RX`, `RZ`), `props.py` (`random`), `ship_concepts.py` (`RX`).
- `ship_concepts_v2.py`: `section_ring` is never called.

## Checked and fine
- Signals connected from robots, reactor, player and level to autoloads aren't disconnected, but Godot drops them when the node is freed, so nothing leaks.
- Every `enemy`-group node implements `can_be_locked`.
- Every level's escape path has 5 points, so `EscapeRun._build_path` can't hit an empty path.
