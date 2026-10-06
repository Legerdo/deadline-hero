"""Authoring script for every stage map -> data/maps/<id>.txt

Usage: python tools/maps.py [s1 s2 ...]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from mapkit import Map  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "maps")


def road(m, pts, width=2, bridge="="):
    """Path that carves through trees and turns water into bridge."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(abs(x1 - x0), abs(y1 - y0)) * 2 + 1
        for i in range(n + 1):
            t = i / n
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            for oy in range(width):
                for ox in range(width):
                    xx, yy = int(round(x)) + ox - width // 2, int(round(y)) + oy - width // 2
                    c = m.get(xx, yy)
                    if c in "~%":
                        m.put(xx, yy, bridge)
                    elif c in "T.,":
                        m.put(xx, yy, ":")


def marks(m, pairs):
    for ch, pts in pairs.items():
        for (x, y) in pts:
            if m.get(x, y) in "T~#":
                print("   !! marker", ch, "on solid at", (x, y), repr(m.get(x, y)))
            m.put(x, y, ch)


# ---------------------------------------------------------------- stage 1
def s1():
    m = Map(56, 34, "T", seed=11)
    m.blob(12, 25, 10.5, 6.5, ".", 0.10)          # village
    m.blob(26, 17, 10, 8.5, ".", 0.20)            # meadow
    m.blob(40, 21, 8, 6.5, ".", 0.20)             # east field
    m.blob(45, 8, 8.5, 5, ".", 0.10)              # boss hill
    m.blob(38, 12, 5, 3.5, ".", 0.20)             # connector
    m.blob(7, 5, 4.5, 2.8, ".", 0.05)             # secret grove
    m.clean_thin()
    m.line([(35, 0), (34, 6), (32, 12), (33, 18), (31, 25), (32, 33)], "~", 2)
    road(m, [(11, 26), (16, 24), (21, 21), (27, 18), (33, 17), (37, 14), (42, 10), (45, 8)], 2)
    m.line([(9, 19), (9, 13), (8, 9), (7, 7)], "^", 1, only="T")
    m.scatter(2, 2, 53, 31, ",", 0.07)
    m.border("T", 1)
    marks(m, {
        "@": [(11, 28)], "H": [(6, 21)], "h": [(17, 21)], "W": [(12, 21)], "E": [(8, 24)],
        "M": [(15, 25)], "K": [(5, 27)], "C": [(20, 27)], "P": [(22, 23)],
        "X": [(5, 5)], "*": [(9, 4)], "g": [(7, 6)], "Y": [(44, 25)], "Z": [(22, 10)],
        "s": [(19, 29), (24, 25), (16, 30), (26, 24), (21, 26)],
        "S": [(27, 21), (21, 14), (28, 23)],
        "1": [(9, 20)],
        "m": [(25, 13), (19, 17), (29, 15)],
        "n": [(28, 10), (23, 19), (30, 21)],
        "b": [(37, 20), (41, 23), (36, 25)],
        "v": [(45, 19), (40, 26)],
        "w": [(39, 12), (43, 13)],
        "q": [(49, 11)],
        "B": [(46, 6)],
    })
    return m


# ---------------------------------------------------------------- stage 2: broken bridge
def s2():
    m = Map(60, 36, "T", seed=22)
    m.blob(15, 28, 12, 5.5, ".", 0.10)            # town
    m.blob(31, 25, 9, 4.5, ".", 0.20)             # south meadow
    m.blob(48, 27, 9, 5.5, ".", 0.20)             # east woods clearing (goblins)
    m.blob(7, 32, 4.5, 2.2, ".", 0.05)            # SW nook
    m.rect(9, 20, 54, 21, ".", only="T")          # south bank strip
    m.rect(8, 11, 54, 12, ".", only="T")          # north bank strip
    m.blob(30, 6, 10, 4.2, ".", 0.08)             # troll arena
    m.blob(14, 8, 7, 3.5, ".", 0.20)              # NW field
    m.blob(47, 7, 8, 4, ".", 0.20)                # NE field
    m.clean_thin()
    m.rect(1, 14, 58, 18, "~")                    # the river (5 rows)
    m.rect(1, 13, 58, 13, "T")
    m.rect(1, 19, 58, 19, "T")
    m.blob(12, 16, 5, 0.9, "T", 0.0, only="~")    # a few islands of reeds
    m.blob(44, 16, 4, 0.9, "T", 0.0, only="~")
    road(m, [(14, 29), (20, 25), (26, 22), (29, 21)], 2)
    road(m, [(29, 21), (29, 12)], 2)              # bridge span through both banks
    road(m, [(29, 12), (30, 9), (30, 6)], 2)
    for y in range(14, 19):                       # the broken bridge planks
        for x in (28, 29, 30):
            if m.get(x, y) == "=":
                m.put(x, y, "%")
    # secret west route: hidden forest trail + a mossy log bridge
    m.line4([(8, 21), (4, 21), (4, 19)], "^", 1, only="T")
    m.line4([(4, 19), (4, 13)], "=", 1, only="~")
    m.line4([(4, 19), (4, 13)], "^", 1, only="T")
    m.line4([(4, 13), (4, 10), (7, 10), (7, 9)], "^", 1, only="T")
    m.blob(3, 5, 2, 1.5, ".", 0.0)                # hidden nook (star)
    m.line4([(4, 10), (4, 7)], "^", 1, only="T")
    m.scatter(2, 2, 57, 33, ",", 0.06)
    m.border("T", 1)
    marks(m, {
        "@": [(14, 30)], "H": [(9, 26)], "h": [(21, 25)], "J": [(17, 27)], "M": [(11, 29)], "C": [(24, 29)],
        "K": [(11, 20)], "P": [(26, 21)], "R": [(29, 20)], "F": [(47, 21)], "2": [(47, 11)], "G": [(50, 11)],
        "3": [(50, 21)], "4": [(9, 21)], "X": [(6, 32)], "Y": [(52, 6)], "Z": [(54, 29)], "*": [(3, 5)], "g": [(4, 16)],
        "c": [(18, 21), (24, 20), (35, 21)], "d": [(40, 20), (33, 26), (13, 20)], "e": [(44, 21), (37, 24)],
        "s": [(20, 31), (25, 26), (8, 31)],
        "o": [(46, 27), (51, 29)], "O": [(55, 25)],
        "w": [(15, 8), (22, 11), (41, 11)], "q": [(45, 7), (52, 9)], "n": [(12, 10), (37, 12)],
        "B": [(30, 5)],
    })
    return m


# ---------------------------------------------------------------- stage 3: dark mine
def s3():
    m = Map(58, 38, "T", seed=33)
    m.blob(9, 32, 6.5, 3.6, ".", 0.08)            # camp (lit)
    m.line4([(8, 28), (8, 20)], ".", 2)           # west shaft
    m.blob(17, 18, 7, 3.4, ".", 0.18)             # chamber A
    m.line4([(21, 15), (21, 8)], ".", 2)          # north tunnel
    m.blob(29, 6, 7, 2.8, ".", 0.12)              # chamber C (lever)
    m.line4([(36, 5), (44, 5)], ".", 2)           # C -> golem hall
    m.blob(50, 5, 6, 3.3, ".", 0.06)              # golem hall
    m.line4([(15, 31), (50, 31)], ".", 2)         # south rail tunnel
    m.line4([(50, 31), (50, 9)], ".", 2)          # east rail shaft (to golem hall)
    m.blob(35, 24, 6, 3, ".", 0.18)               # chamber B
    m.line4([(35, 27), (35, 31)], ".", 2)         # B <-> rail tunnel
    m.line4([(24, 19), (28, 19), (28, 22), (30, 22)], ".", 2)   # A <-> B
    m.line4([(41, 24), (49, 24)], ".", 1)         # B -> east shaft (cracked wall)
    m.blob(5, 11, 3, 2, ".", 0.0)                 # hidden side cave (time beetle)
    m.line4([(8, 19), (8, 13), (6, 13)], ".", 1)  # west shaft -> side cave (cracked wall)
    m.rect(54, 29, 56, 33, ".")                   # secret room (star)
    m.line4([(52, 31), (53, 31)], ".", 1)
    m.clean_thin()
    road(m, [(13, 31), (50, 31)], 1)              # rails
    road(m, [(50, 31), (50, 9)], 1)
    m.scatter(2, 2, 55, 35, ",", 0.05)
    m.border("T", 1)
    marks(m, {
        "@": [(8, 33)], "D": [(12, 33)], "M": [(5, 31)], "C": [(14, 34)], "Q": [(12, 31)],
        "t": [(5, 30), (13, 30), (16, 16), (29, 4), (47, 3), (35, 22), (48, 31)],
        "Y": [(19, 20), (28, 8), (38, 25), (30, 31), (51, 18)],
        "W": [(46, 24), (8, 16), (53, 31)], "L": [(33, 5)],
        "5": [(50, 31)], "6": [(50, 10)],
        "X": [(12, 17), (39, 23)], "*": [(55, 31)], "g": [(4, 11)], "$": [(6, 11)],
        "b": [(8, 24), (19, 31), (26, 31)], "v": [(14, 19), (33, 25), (42, 31)],
        "r": [(22, 17), (31, 23)], "R": [(24, 6), (38, 26), (50, 20)], "E": [(32, 7), (47, 6)],
        "B": [(51, 5)],
    })
    return m


# ---------------------------------------------------------------- stage 4: haunted manor
def s4():
    m = Map(56, 40, "#", seed=44)
    def room(x0, y0, x1, y1):
        m.rect(x0, y0, x1, y1, ".")
    room(20, 28, 35, 37)      # foyer (start)
    room(4, 26, 15, 36)       # chapel (west)
    room(40, 26, 51, 36)      # east hall
    room(4, 13, 15, 22)       # west wing (plate B)
    room(40, 13, 51, 22)      # east wing (plate A)
    room(19, 15, 36, 23)      # grand corridor
    room(22, 9, 33, 11)       # gallery (behind gate)
    room(10, 2, 45, 6)        # ballroom (boss)
    # doors / corridors
    room(16, 31, 19, 32)      # foyer - chapel
    room(36, 31, 39, 32)      # foyer - east hall
    room(27, 24, 28, 27)      # foyer - corridor
    room(9, 23, 10, 25)       # chapel - west wing
    room(45, 23, 46, 25)      # east hall - east wing
    room(16, 17, 18, 18)      # west wing - corridor
    room(37, 17, 39, 18)      # east wing - corridor
    room(9, 7, 10, 12)        # west wing - ballroom
    room(45, 7, 46, 12)       # east wing - ballroom
    room(27, 12, 27, 14)      # corridor - gallery (gate, 1 wide)
    m.line([(27, 36), (27, 24), (27, 16)], ":", 2, only=".,")
    m.line([(20, 32), (10, 32)], ":", 2, only=".,")
    m.line([(36, 32), (46, 32), (46, 24), (46, 18)], ":", 2, only=".,")
    m.line([(10, 25), (10, 17), (10, 7), (14, 4), (42, 4)], ":", 2, only=".,")
    m.line([(46, 18), (46, 7)], ":", 2, only=".,")
    m.scatter(4, 2, 51, 37, ",", 0.05)
    marks(m, {
        "@": [(27, 35)], "S": [(24, 30)], "N": [(8, 29)], "C": [(31, 30)], "P": [(22, 34)],
        "p": [(49, 15)], "q": [(6, 15)], "G": [(27, 13)], "l": [(25, 10)], "*": [(31, 10)],
        "o": [(5, 35), (50, 35), (5, 14), (50, 21), (34, 22), (20, 22), (13, 27), (42, 27)],
        "X": [(14, 35), (41, 35)], "g": [(33, 29)],
        "b": [(22, 36), (33, 36)], "h": [(12, 31), (43, 31), (47, 34)], "H": [(8, 18), (44, 16), (30, 18)],
        "k": [(48, 30), (6, 33), (23, 20)], "K": [(12, 16), (42, 20), (33, 17)], "y": [(21, 29), (35, 33)], "Y": [(24, 16), (8, 20), (48, 19)],
        "B": [(27, 3)],
    })
    return m


# ---------------------------------------------------------------- stage 5: mirror temple
def s5():
    m = Map(58, 38, "#", seed=55)
    def room(x0, y0, x1, y1, ch="."):
        m.rect(x0, y0, x1, y1, ch)
    room(20, 27, 37, 36)      # entrance court
    room(3, 24, 15, 35)       # west hall
    room(42, 24, 54, 35)      # east hall
    room(3, 11, 15, 20)       # west shrine (lever 1)
    room(42, 11, 54, 20)      # east shrine (lever 2)
    room(18, 14, 39, 22)      # middle cloister
    room(16, 2, 41, 9)        # sanctum (boss)
    room(16, 30, 19, 31)      # court - west hall
    room(38, 30, 41, 31)      # court - east hall
    room(8, 21, 9, 23)        # west hall - west shrine
    room(47, 21, 48, 23)      # east hall - east shrine
    room(16, 17, 17, 17)      # west shrine - cloister (gate A, 1 high)
    room(40, 17, 41, 17)      # east shrine - cloister (gate B, 1 high)
    room(28, 23, 28, 26)      # court - cloister (key gate, 1 wide)
    room(28, 10, 29, 13)      # cloister - sanctum
    # teal channels in the cloister
    m.rect(21, 16, 25, 20, "~")
    m.rect(32, 16, 36, 20, "~")
    m.rect(24, 5, 26, 7, "~")
    m.rect(31, 5, 33, 7, "~")
    m.line([(28, 35), (28, 23), (28, 10)], ":", 2, only=".,")
    m.line([(20, 31), (9, 31), (9, 21), (9, 17), (16, 17)], ":", 2, only=".,")
    m.line([(37, 31), (48, 31), (48, 21), (48, 17), (41, 17)], ":", 2, only=".,")
    m.line([(17, 17), (27, 17)], ":", 1, only=".,")
    m.line([(40, 17), (30, 17)], ":", 1, only=".,")
    for x in range(21, 26):
        m.put(x, 17, "=")
    for x in range(32, 37):
        m.put(x, 17, "=")
    m.scatter(3, 2, 54, 35, ",", 0.05)
    marks(m, {
        "@": [(28, 34)], "V": [(25, 30)], "v": [(29, 11)], "M": [(22, 33)], "C": [(34, 33)],
        "K": [(28, 24)], "a": [(16, 17)], "d": [(41, 17)], "L": [(6, 12)], "l": [(51, 12)],
        "X": [(4, 34), (53, 25)], "*": [(53, 34)], "g": [(12, 12)], "$": [(46, 33)], "o": [(19, 21), (38, 21)],
        "w": [(24, 29), (33, 28), (7, 27)], "W": [(12, 32), (44, 27), (50, 33)],
        "s": [(22, 35), (35, 35), (5, 29)], "S": [(10, 25), (46, 29), (52, 31)],
        "z": [(6, 18), (12, 14), (45, 18), (51, 15)], "Z": [(20, 20), (37, 15), (27, 20)],
        "B": [(28, 4)],
    })
    return m


# ---------------------------------------------------------------- stage 6: ember volcano
def s6():
    m = Map(60, 38, "T", seed=66)
    m.blob(8, 32, 6, 4, ".", 0.1)                 # base camp (high)
    m.blob(24, 30, 9, 5, "8", 0.15)               # lowland A (forge) floods first
    m.blob(44, 28, 8, 5, "9", 0.15)               # lowland B (statue) floods second
    m.blob(14, 18, 7, 5, ".", 0.2)                # west ridge (high)
    m.blob(33, 16, 7, 4.5, ".", 0.2)              # middle ridge
    m.blob(48, 6, 8, 4, ".", 0.08)                # summit (drake)
    m.line([(12, 30), (16, 24), (14, 18)], ".", 3)
    m.line([(20, 18), (28, 16), (33, 16)], ".", 3)
    m.line([(38, 14), (44, 9), (48, 6)], ".", 3)
    m.line([(30, 28), (36, 21), (34, 17)], "8", 2)
    m.line([(40, 26), (38, 20)], "9", 2)
    m.blob(30, 22, 2, 1.5, "~", 0.0)
    m.blob(55, 18, 3, 6, "~", 0.1)
    m.blob(40, 36, 10, 2, "~", 0.1)
    m.blob(20, 8, 6, 3, "~", 0.2)
    m.blob(4, 10, 2.5, 2, ".", 0.0)               # hidden ledge (star)
    m.line4([(7, 15), (7, 13), (5, 13), (5, 12)], "^", 1, only="T")
    m.clean_thin()
    road(m, [(8, 32), (14, 26), (15, 19), (22, 17), (32, 16), (40, 13), (47, 7)], 2)
    m.scatter(2, 2, 57, 35, ",", 0.06)
    m.border("T", 1)
    # zone chars 8/9 are floor markers the stage JSON floods with lava later
    marks(m, {
        "@": [(7, 33)], "Q": [(24, 31)], "C": [(45, 29)], "N": [(10, 31)], "P": [(13, 28)],
        "X": [(18, 32), (50, 25), (37, 15)], "*": [(4, 10)], "g": [(16, 15)], "$": [(28, 33)],
        "s": [(11, 27), (20, 28), (27, 27)], "S": [(17, 20), (30, 31), (41, 28)],
        "x": [(12, 16), (35, 18), (46, 30)],
        "r": [(29, 15), (36, 14)], "b": [(22, 33), (48, 26)], "k": [(42, 11), (50, 8)],
        "B": [(49, 5)],
    })
    return m


# ---------------------------------------------------------------- stage 7: clock tower
def s7():
    m = Map(56, 46, "~", seed=77)
    def room(x0, y0, x1, y1, ch="."):
        m.rect(x0, y0, x1, y1, ch)
    # outer walls ring each floor (void outside)
    m.rect(6, 33, 49, 44, "#")
    room(8, 35, 47, 42)       # floor 1: entrance hall
    m.rect(6, 18, 49, 31, "#")
    room(8, 20, 47, 29)       # floor 2: gear hall
    m.rect(8, 1, 47, 16, "#")
    room(10, 3, 45, 14)       # floor 3: bell chamber (boss)
    # pillars / gear blocks
    for (x, y) in ((16, 37), (38, 37), (16, 40), (38, 40)):
        m.rect(x, y, x + 1, y + 1, "#")
    for (x, y) in ((14, 22), (22, 25), (32, 22), (40, 25)):
        m.rect(x, y, x + 2, y + 1, "#")
    m.rect(12, 5, 13, 6, "~")
    m.rect(42, 5, 43, 6, "~")
    m.rect(12, 11, 13, 12, "~")
    m.rect(42, 11, 43, 12, "~")
    m.line([(27, 41), (27, 36), (44, 36)], ":", 2, only=".,")
    m.line([(44, 27), (27, 27), (11, 27), (11, 21)], ":", 2, only=".,")
    m.line([(27, 13), (27, 8)], ":", 2, only=".,")
    m.scatter(8, 3, 47, 42, ",", 0.04)
    marks(m, {
        "@": [(27, 41)], "M": [(20, 38)], "C": [(34, 38)], "N": [(24, 39)], "P": [(30, 41)],
        "U": [(45, 36)], "2": [(44, 27)], "V": [(10, 21)], "3": [(27, 13)], "Z": [(44, 21)], "z": [(44, 35)],
        "X": [(9, 36), (46, 28), (20, 21)], "*": [(9, 28)], "g": [(46, 41)], "$": [(30, 24)],
        "t": [(12, 39), (21, 36), (36, 41), (41, 38)],
        "e": [(12, 37), (22, 41), (33, 36), (41, 41), (30, 39)], "E": [(44, 39), (10, 41), (19, 36)],
        "k": [(18, 21), (29, 21), (37, 28), (25, 28)], "K": [(12, 24), (36, 24), (43, 22)], "j": [(20, 26), (34, 26)],
        "B": [(27, 7)],
    })
    return m


STAGES = {"s1": s1, "s2": s2, "s3": s3, "s4": s4, "s5": s5, "s6": s6, "s7": s7}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    names = sys.argv[1:] or list(STAGES.keys())
    for nm in names:
        print(nm)
        mp = STAGES[nm]()
        mp.save(os.path.join(OUT, nm + ".txt"), "generated by tools/maps.py - edit there")
        print(mp.text())
