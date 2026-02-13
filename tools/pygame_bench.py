from __future__ import annotations

import math
import sys
import time

import pygame

WIDTH, HEIGHT = 1280, 720
DEFAULT_SPRITES = 200
STRESS_SPRITES = 2000
DEFAULT_SECONDS = 8.0
DEFAULT_CAP = 60


def _parse_args() -> tuple[int, float, int, bool]:
    sprites = DEFAULT_SPRITES
    seconds = DEFAULT_SECONDS
    cap = DEFAULT_CAP
    vsync = "--vsync" in sys.argv

    if "--stress" in sys.argv:
        sprites = STRESS_SPRITES
        cap = 0

    if "--sprites" in sys.argv:
        idx = sys.argv.index("--sprites")
        if idx + 1 < len(sys.argv):
            try:
                sprites = max(1, int(sys.argv[idx + 1]))
            except ValueError:
                pass

    if "--seconds" in sys.argv:
        idx = sys.argv.index("--seconds")
        if idx + 1 < len(sys.argv):
            try:
                seconds = float(sys.argv[idx + 1])
            except ValueError:
                pass

    if "--cap" in sys.argv:
        idx = sys.argv.index("--cap")
        if idx + 1 < len(sys.argv):
            try:
                cap = max(0, int(sys.argv[idx + 1]))
            except ValueError:
                pass

    if "--uncap" in sys.argv:
        cap = 0

    return sprites, max(1.0, seconds), cap, vsync


def main() -> None:
    sprites, seconds, cap, vsync = _parse_args()
    pygame.init()
    vsync_enabled = vsync
    try:
        screen = pygame.display.set_mode((WIDTH, HEIGHT), vsync=1 if vsync else 0)
    except TypeError:
        screen = pygame.display.set_mode((WIDTH, HEIGHT))
        if vsync:
            vsync_enabled = False
            print("pygame: vsync flag not supported; running without vsync")

    pygame.display.set_caption("pygame stress bench")
    clock = pygame.time.Clock()
    start = time.perf_counter()
    tick_last = start
    tick_frames = 0
    total_frames = 0

    running = True
    while running:
        for e in pygame.event.get():
            if e.type == pygame.QUIT:
                running = False

        t = time.perf_counter() - start
        screen.fill((15, 18, 22))

        for i in range(sprites):
            x = int(200 + i * 4 + 30 * math.sin(t + i))
            y = int(150 + i * 3 + 30 * math.cos(t * 1.2 + i))
            pygame.draw.rect(
                screen,
                (120, 140, 160),
                pygame.Rect(x % WIDTH, y % HEIGHT, 80, 120),
                border_radius=14,
            )

        pygame.display.flip()
        if cap > 0:
            clock.tick(cap)
        else:
            clock.tick(0)

        now = time.perf_counter()
        tick_frames += 1
        total_frames += 1
        if now - tick_last >= 1.0:
            fps = tick_frames / (now - tick_last)
            label = "vsync" if vsync_enabled else "no-vsync"
            cap_label = f"cap={cap}" if cap > 0 else "uncapped"
            print(f"pygame fps ({label} {cap_label} sprites={sprites}): {fps:5.1f}")
            tick_frames = 0
            tick_last = now

        if now - start >= seconds:
            break

    avg = total_frames / max(0.001, (time.perf_counter() - start))
    label = "vsync" if vsync_enabled else "no-vsync"
    cap_label = f"cap={cap}" if cap > 0 else "uncapped"
    print(f"pygame avg ({label} {cap_label} sprites={sprites}): {avg:5.1f}")
    pygame.quit()


if __name__ == "__main__":
    main()
