"""Shared vocabulary for level layout files: cells are carved out of solid rock."""
import random

S = 10.0  # metres per cell
cells = {}


def carve(a, b, zone):
    for i in range(min(a[0], b[0]), max(a[0], b[0]) + 1):
        for j in range(min(a[1], b[1]), max(a[1], b[1]) + 1):
            for k in range(min(a[2], b[2]), max(a[2], b[2]) + 1):
                cells[(i, j, k)] = zone


def fill(a, b):
    for i in range(min(a[0], b[0]), max(a[0], b[0]) + 1):
        for j in range(min(a[1], b[1]), max(a[1], b[1]) + 1):
            for k in range(min(a[2], b[2]), max(a[2], b[2]) + 1):
                cells.pop((i, j, k), None)


def c(i, j, k):
    return [i * S, j * S, k * S]


# ---------------------------------------------------------------------- mission builder
AXES = {"x": 0, "y": 1, "z": 2}
SIDES = {"west": (-1, 0, 0), "east": (1, 0, 0), "north": (0, 0, -1)}
SPINE = 10
ESCAPE_LEGS = (17, 11, 8, 18)


def _box_cells(a, b):
    return {(i, j, k) for i in range(min(a[0], b[0]), max(a[0], b[0]) + 1)
            for j in range(min(a[1], b[1]), max(a[1], b[1]) + 1)
            for k in range(min(a[2], b[2]), max(a[2], b[2]) + 1)}


def _piece(a, b, zone, allowed):
    """Carves a box and refuses to touch anything but the piece it connects to."""
    new = _box_cells(a, b)
    for cell in new:
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
            near = (cell[0] + d[0], cell[1] + d[1], cell[2] + d[2])
            if near in cells and near not in new and near not in allowed:
                raise ValueError(f"piece {a}-{b} touches unrelated cell {near}")
    for cell in new:
        cells[cell] = zone
    return new


def _add(p, d, n):
    return (p[0] + d[0] * n, p[1] + d[1] * n, p[2] + d[2] * n)


def _route(start, d, l1, bends, l2, zone, allowed):
    """A tunnel in legs. Returns its end cell, the last leg's cells and all its cells."""
    end = _add(start, d, l1 - 1)
    leg = _piece(start, end, zone, allowed)
    route = list(leg)
    for axis, amount in bends:
        step = [0, 0, 0]
        step[AXES[axis]] = 1 if amount > 0 else -1
        turn = _add(end, step, abs(amount))
        leg = _piece(end, turn, zone, leg)
        route += list(leg)
        end = turn
    final = _add(end, d, l2)
    leg = _piece(end, final, zone, leg)
    route += list(leg)
    return final, leg, route


def _room_from(end, d, room, allowed):
    hx, hy, hz, zone = room
    half = (hx, hy, hz)
    axis = next(i for i in range(3) if d[i])
    center = list(end)
    center[axis] += d[axis] * (half[axis] + 1)
    center = tuple(center)
    a = (center[0] - hx, center[1] - hy, center[2] - hz)
    b = (center[0] + hx, center[1] + hy, center[2] + hz)
    _piece(a, b, zone, allowed)
    return center, a, b


def _try(attempts, build):
    """Retries a randomised carve, undoing any partial work when it collides."""
    for _ in range(attempts):
        snapshot = dict(cells)
        try:
            return build()
        except ValueError:
            cells.clear()
            cells.update(snapshot)
    return None


def secret_room(tunnel_cell, side, loot):
    """A concealed side room. Returns its door, flush with the tunnel wall, and its loot."""
    door_cell = _add(tunnel_cell, side, 1)
    corridor_end = _add(door_cell, side, 2)
    leg = _piece(door_cell, corridor_end, "metal", {tunnel_cell})
    center, a, b = _room_from(corridor_end, side, (2, 1, 2, "metal"), leg)
    room = sorted(_box_cells(a, b))
    door = {"id": f"secret_{door_cell}", "cell": list(door_cell), "axis": "x" if side[0] else "z", "lock": "secret",
            "offset": [-side[0] * S * 0.5, 0.0, -side[2] * S * 0.5]}
    spaced = room[:: max(1, len(room) // max(1, len(loot)))]
    return door, [(kind, _world(cell)) for kind, cell in zip(loot, spaced)]


def _world(cell):
    return [cell[0] * S, cell[1] * S, cell[2] * S]


def mission(spec):
    """Turns a compact level plan into all the data a layout module must define."""
    r = random.Random(spec["seed"])
    out = {"DOORS": [], "ROBOTS": [], "TURRETS": [], "PICKUPS": [], "MINES": [], "ASTRONAUTS": []}

    def spots(box_cells, n, keep_clear=None):
        pool = sorted(box_cells)
        if keep_clear is not None:
            pool = [c_ for c_ in pool if max(abs(c_[i] - keep_clear[i]) for i in range(3)) >= 4]
        return r.sample(pool, min(n, len(pool)))

    def populate(volume, area, keep_clear=None):
        for kind, cell in zip(area.get("enemies", []), spots(volume, len(area.get("enemies", [])), keep_clear)):
            out["ROBOTS"].append((kind, _world(cell)))
        for kind, cell in zip(area.get("pick", []), spots(volume, len(area.get("pick", [])), keep_clear)):
            out["PICKUPS"].append((kind, _world(cell)))
        for cell in spots(volume, area.get("astronauts", 0), keep_clear):
            out["ASTRONAUTS"].append(_world(cell))

    pending_mounts = []
    pending_wires = []

    def wall_mounts(a, b, n):
        pending_mounts.append((a, b, n))

    def place_wall_mounts(a, b, n):
        options = []
        for j in range(a[1] + 1, b[1]):
            for k in range(a[2], b[2] + 1):
                for x, outward in ((b[0], 1), (a[0], -1)):
                    if (x + outward, j, k) not in cells:
                        options.append(([x * S + outward * (S / 2 - 0.5), j * S, k * S], [-outward, 0, 0]))
        for pos, normal in r.sample(options, min(n, len(options))):
            out["TURRETS"].append((pos, normal))

    def tunnel_hazards(route, d, area):
        enemy_cells = spots(set(route), len(area.get("tunnel", [])) + len(area.get("mines", [])))
        for kind, cell in zip(area.get("tunnel", []), enemy_cells):
            out["ROBOTS"].append((kind, _world(cell)))
        for kind, cell in zip(area.get("mines", []), enemy_cells[len(area.get("tunnel", [])):]):
            if kind == "tripwire":
                pending_wires.append((cell, d))
            else:
                out["MINES"].append({"type": kind, "pos": _world(cell), "normal": [0, 1, 0]})

    def add_door(cell, d, lock):
        if lock:
            out["DOORS"].append({"id": f"{lock}_{len(out['DOORS'])}", "cell": list(cell), "axis": "x" if d[0] else "z", "lock": lock})

    # Launch bay and spine.
    bay = _piece((-2, 0, 0), (2, 2, 4), "metal", set())
    spine = _piece((0, 1, -SPINE), (0, 1, -1), "metal", bay)
    hw, hh, hd, hub_zone = spec["hub"]
    hub_center = (0, 1, -SPINE - 1 - hd)
    hub_a = (-hw, 1 - hh, hub_center[2] - hd)
    hub_b = (hw, 1 + hh, hub_center[2] + hd)
    hub = _piece(hub_a, hub_b, hub_zone, spine)
    populate(hub, spec.get("hub_area", {}))
    wall_mounts(hub_a, hub_b, spec.get("hub_area", {}).get("turrets", 0))

    metal_tunnels = []

    def extend(center, a, e, d, room_cells):
        """Grows one more tunnel and room out of a room's far wall."""
        def build():
            wall = e[0] + 1 if d[0] > 0 else a[0] - 1
            start = (wall, center[1] + r.randint(-1, 1), center[2] + r.randint(-2, 2))
            bends = [(r.choice("yz"), r.choice((-6, -5, -4, 4, 5, 6)))]
            if r.random() < 0.5:
                bends.append(("z" if bends[0][0] == "y" else "y", r.choice((-5, -4, 4, 5))))
            zone = r.choice(("metal", "rock"))
            end, leg, route = _route(start, d, r.randint(6, 9), bends, r.randint(5, 8), zone, room_cells)
            size = (r.randint(4, 6), r.randint(2, 3), r.randint(3, 5), r.choice(("metal", "rock")))
            next_center, next_a, next_e = _room_from(end, d, size, leg)
            return route, zone, next_center, next_a, next_e
        return _try(30, build)

    # Side branches: a tunnel, maybe a locked door, and a room at the end.
    for b in spec["branches"]:
        d = SIDES[b["side"]]
        start = (d[0] * (hw + 1), 1 + b.get("y", 0), hub_center[2] + b.get("z", 0))
        end, leg, route = _route(start, d, b["l1"], b.get("bends", []), b["l2"], b.get("tunnel_zone", "metal"), hub)
        add_door(_add(start, d, 2), d, b.get("door"))
        center, a, e = _room_from(end, d, b["room"], leg)
        safe_route = [c_ for c_ in route if c_ != _add(start, d, 2)]
        tunnel_hazards(safe_route, d, b)
        if b.get("tunnel_zone", "metal") == "metal":
            metal_tunnels += [(c_, d) for c_ in safe_route]
        # The key lives at the far end of the chain, so finding it takes exploring.
        keys = [p for p in b.get("pick", []) if p.startswith("key_")]
        area = dict(b, pick=[p for p in b.get("pick", []) if not p.startswith("key_")])
        populate(_box_cells(a, e), area)
        wall_mounts(a, e, b.get("turrets", 0))
        deepest = _box_cells(a, e)
        for _ in range(spec.get("extend", 0)):
            grown = extend(center, a, e, d, _box_cells(a, e))
            if grown is None:
                break
            route, zone, center, a, e = grown
            if zone == "metal":
                metal_tunnels += [(c_, d) for c_ in route]
            filler = spec["filler"]
            tunnel_hazards(route, d, {"tunnel": r.choices(filler, k=2), "mines": r.choices(spec["filler_mines"], k=2)})
            deepest = _box_cells(a, e)
            populate(deepest, {"enemies": r.choices(filler, k=r.randint(3, 5)), "pick": r.choices(("shield", "energy", "ammo"), k=2)})
            wall_mounts(a, e, 1)
        for kind, cell in zip(keys, spots(deepest, len(keys))):
            out["PICKUPS"].append((kind, _world(cell)))

    # The finale: a bending approach, so nothing inside can be seen from its door.
    f = spec["finale"]
    d = SIDES["north"]
    start = (f.get("x", 0), 1 + f.get("y", 0), hub_a[2] - 1)
    end, leg, route = _route(start, d, f["l1"], f["bends"], f["l2"], "metal", hub)
    add_door(_add(start, d, 2), d, f.get("door"))
    center, a, e = _room_from(end, d, f["room"], leg)
    tunnel_hazards([c_ for c_ in route if c_ != _add(start, d, 2)], d, f)
    hy = f["room"][1]
    if f.get("boss"):
        out["ROBOTS"].append(("overseer", _world(center)))
        out["REACTOR"] = None
        out["REACTOR_SCALE"], out["REACTOR_HP"], out["REACTOR_NOVA"] = 2.0, 0.0, False
    else:
        out["REACTOR"] = _world(center)
        out["REACTOR_SCALE"] = min(2.0, (hy * S + S / 2 - 1.0) / 21.0)
        out["REACTOR_HP"] = f["reactor_hp"]
        out["REACTOR_NOVA"] = f.get("nova", True)
    volume = _box_cells(a, e)
    populate(volume, f, center)
    wall_mounts(a, e, f.get("turrets", 0))
    out["ALARM_SPAWNS"] = [_world(c_) for c_ in spots(volume, 4, center)]

    # Secret rooms hide behind plain wall panels along metal tunnels.
    for loot in spec.get("secrets", []):
        if not metal_tunnels:
            # r.choice would raise IndexError, which _try doesn't catch.
            print("[level] no metal tunnel to hide a secret room behind; skipped")
            break

        def place():
            cell, tunnel_dir = r.choice(metal_tunnels)
            if cells.get(cell) != "metal":
                raise ValueError("not metal")
            side = (0, 0, r.choice((-1, 1))) if tunnel_dir[0] else (r.choice((-1, 1)), 0, 0)
            door, items = secret_room(cell, side, loot)
            return door, items
        placed = _try(60, place)
        if placed is not None:
            out["DOORS"].append(placed[0])
            out["PICKUPS"] += placed[1]

    def finish_hazards():
        """Runs last, once every wall that will ever be opened has been opened."""
        for a, b, n in pending_mounts:
            place_wall_mounts(a, b, n)
        for cell, d in pending_wires:
            # Mounted on a side wall, so the beam spans the tunnel.
            for side in ((0, 0, 1), (0, 0, -1)) if d[0] else ((1, 0, 0), (-1, 0, 0)):
                if _add(cell, side, 1) not in cells:
                    pos = [cell[i] * S + side[i] * (S / 2 - 0.5) for i in range(3)]
                    out["MINES"].append({"type": "tripwire", "pos": pos, "normal": [-v for v in side]})
                    break

    # The escape tunnel leaves the east wall; every level's is the same length.
    door = (e[0] + 1, center[1], center[2])
    out["DOORS"].append({"id": "escape", "cell": list(door), "axis": "x", "lock": "reactor"})
    run = (door[0] + ESCAPE_LEGS[0], door[1], door[2])
    north = (run[0], run[1], run[2] - ESCAPE_LEGS[1])
    up = (north[0], north[1] + ESCAPE_LEGS[2], north[2])
    end_cell = (up[0] + ESCAPE_LEGS[3], up[1], up[2])
    legs = _piece(door, run, "metal", volume)
    legs = _piece(run, north, "rock", legs)
    legs = _piece(north, up, "rock", legs)
    _piece(up, end_cell, "metal", legs)
    out["ESCAPE_END"] = _world(end_cell)
    out["ESCAPE_PATH"] = [_world(p) for p in (door, run, north, up, end_cell)]
    out["ESCAPE_TRIGGER"] = _world(_add(door, (1, 0, 0), 3))
    finish_hazards()
    out["CATCH_UP"] = [c(0, 1, -k) for k in range(2, 10)]
    out["DETAIL_DENSITY"] = 0.5
    return out
