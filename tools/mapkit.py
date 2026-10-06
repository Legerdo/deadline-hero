"""Tiny ASCII map painter used to author data/maps/*.txt.

Legend (engine side, see scripts/game/map_builder.gd):
  .  floor   ,  floor+decor   :  path   ~  liquid   T  trees/rocks
  #  wall    =  bridge        %  broken bridge      ^  secret passage (walkable, hidden)
Any other character is an entity marker defined in the stage JSON.
"""
import math
import random


class Map:
    def __init__(self, w, h, fill="T", seed=1):
        self.w, self.h = w, h
        self.g = [[fill] * w for _ in range(h)]
        self.rng = random.Random(seed)

    def inb(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h

    def get(self, x, y):
        return self.g[y][x] if self.inb(x, y) else "T"

    def put(self, x, y, ch):
        if self.inb(x, y):
            self.g[y][x] = ch

    def rect(self, x0, y0, x1, y1, ch, only=None):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if only is None or self.get(x, y) in only:
                    self.put(x, y, ch)

    def blob(self, cx, cy, rx, ry, ch=".", noise=0.18, only=None):
        ph = [self.rng.random() * 6.28 for _ in range(3)]
        for y in range(int(cy - ry - 2), int(cy + ry + 3)):
            for x in range(int(cx - rx - 2), int(cx + rx + 3)):
                dx, dy = (x - cx) / max(rx, 0.5), (y - cy) / max(ry, 0.5)
                a = math.atan2(dy, dx)
                r = 1 + noise * (math.sin(3 * a + ph[0]) * 0.6 + math.sin(5 * a + ph[1]) * 0.4)
                if dx * dx + dy * dy <= r * r:
                    if only is None or self.get(x, y) in only:
                        self.put(x, y, ch)

    def line(self, pts, ch, width=1, only=None):
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            n = max(abs(x1 - x0), abs(y1 - y0)) * 2 + 1
            for i in range(n + 1):
                t = i / n
                x = x0 + (x1 - x0) * t
                y = y0 + (y1 - y0) * t
                for oy in range(width):
                    for ox in range(width):
                        xx, yy = int(round(x)) + ox - width // 2, int(round(y)) + oy - width // 2
                        if only is None or self.get(xx, yy) in only:
                            self.put(xx, yy, ch)

    def line4(self, pts, ch, width=1, only=None):
        """Axis-aligned (4-connected) polyline: x first, then y."""
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            x, y = x0, y0
            seq = [(x, y)]
            while x != x1:
                x += 1 if x1 > x else -1
                seq.append((x, y))
            while y != y1:
                y += 1 if y1 > y else -1
                seq.append((x, y))
            for (px, py) in seq:
                for oy in range(width):
                    for ox in range(width):
                        xx, yy = px + ox, py + oy
                        if only is None or self.get(xx, yy) in only:
                            self.put(xx, yy, ch)

    def scatter(self, x0, y0, x1, y1, ch, prob, on="."):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if self.get(x, y) == on and self.rng.random() < prob:
                    self.put(x, y, ch)

    def border(self, ch="T", t=1):
        for y in range(self.h):
            for x in range(self.w):
                if x < t or y < t or x >= self.w - t or y >= self.h - t:
                    self.put(x, y, ch)

    def clean_thin(self, ch="T", passes=2):
        """Remove 1-cell wide spikes of `ch` that look noisy with the dual grid."""
        for _ in range(passes):
            kill = []
            for y in range(1, self.h - 1):
                for x in range(1, self.w - 1):
                    if self.g[y][x] != ch:
                        continue
                    n = sum(self.g[y + dy][x + dx] == ch for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                    if n <= 1:
                        kill.append((x, y))
            for x, y in kill:
                self.g[y][x] = "."

    def text(self):
        return "\n".join("".join(r) for r in self.g) + "\n"

    def save(self, path, header=""):
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            if header:
                for l in header.strip().split("\n"):
                    f.write("; " + l + "\n")
            f.write(self.text())
