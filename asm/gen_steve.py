#!/usr/bin/env python3
"""
Generate Minecraft Steve model for C64 3D renderer.
Outputs 6502 assembly data for vertices and face indices.
Supports walking animation with swinging arms and legs.
"""

import math
import sys

NUM_FRAMES = 24
MAX_SWING_ANGLE = math.pi / 6  # 30 degrees max swing


def generate_box_vertices(x0, x1, y0, y1, z0, z1):
    """
    Generate 8 vertices for a box.

    Vertex layout:
         3-------2       Y+  Z+
        /|      /|       |  /
       0-------1 |       | /
       | 7-----|-6       |/____X+
       |/      |/
       4-------5
    """
    return [
        (x0, y1, z0),  # 0: front top left
        (x1, y1, z0),  # 1: front top right
        (x1, y1, z1),  # 2: back top right
        (x0, y1, z1),  # 3: back top left
        (x0, y0, z0),  # 4: front bottom left
        (x1, y0, z0),  # 5: front bottom right
        (x1, y0, z1),  # 6: back bottom right
        (x0, y0, z1),  # 7: back bottom left
    ]


def generate_box_faces(base_vertex, flip_winding=False):
    """Generate 12 triangles for a box starting at base_vertex."""
    B = base_vertex

    faces = [
        # Front face (z = z0)
        (B+0, B+1, B+5, "front"),
        (B+0, B+5, B+4, "front"),
        # Back face (z = z1)
        (B+2, B+3, B+7, "back"),
        (B+2, B+7, B+6, "back"),
        # Top face (y = y1)
        (B+0, B+3, B+2, "top"),
        (B+0, B+2, B+1, "top"),
        # Bottom face (y = y0)
        (B+4, B+5, B+6, "bottom"),
        (B+4, B+6, B+7, "bottom"),
        # Right face (x = x1)
        (B+1, B+2, B+6, "right"),
        (B+1, B+6, B+5, "right"),
        # Left face (x = x0)
        (B+0, B+4, B+7, "left"),
        (B+0, B+7, B+3, "left"),
    ]

    if flip_winding:
        faces = [(i, k, j, name) for (i, j, k, name) in faces]

    return faces


def rotate_yz(vertices, pivot, angle):
    """
    Rotate vertices around pivot point in YZ plane.

    Args:
        vertices: list of (x, y, z) tuples
        pivot: (px, py, pz) pivot point
        angle: rotation angle in radians

    Returns:
        list of rotated (x, y, z) tuples
    """
    px, py, pz = pivot
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)

    result = []
    for x, y, z in vertices:
        # Translate to pivot
        dy = y - py
        dz = z - pz
        # Rotate in YZ plane
        new_y = py + dy * cos_a - dz * sin_a
        new_z = pz + dy * sin_a + dz * cos_a
        # X unchanged
        result.append((x, new_y, new_z))

    return result


def generate_steve_frame(frame_num):
    """Generate vertices for one animation frame."""

    # Animation angle: sin wave over 24 frames
    t = 2 * math.pi * frame_num / NUM_FRAMES
    swing = MAX_SWING_ANGLE * math.sin(t)

    # Box definitions: (name, x0, x1, y0, y1, z0, z1)
    # Static parts
    head = ("head", -30, 30, 60, 120, -30, 30)
    body = ("body", -30, 30, -30, 60, -15, 15)

    # Animated parts with their pivots (center of top face)
    right_arm_def = ("right_arm", 30, 60, -30, 60, -15, 15)
    left_arm_def = ("left_arm", -60, -30, -30, 60, -15, 15)
    right_leg_def = ("right_leg", 0, 30, -120, -30, -15, 15)
    left_leg_def = ("left_leg", -30, 0, -120, -30, -15, 15)

    all_vertices = []

    # Head (vertices 0-7) - static
    name, x0, x1, y0, y1, z0, z1 = head
    all_vertices.extend(generate_box_vertices(x0, x1, y0, y1, z0, z1))

    # Body (vertices 8-15) - static
    name, x0, x1, y0, y1, z0, z1 = body
    all_vertices.extend(generate_box_vertices(x0, x1, y0, y1, z0, z1))

    # Right arm (vertices 16-23) - swings with -sin(t)
    name, x0, x1, y0, y1, z0, z1 = right_arm_def
    pivot = ((x0 + x1) / 2, y1, (z0 + z1) / 2)  # shoulder
    verts = generate_box_vertices(x0, x1, y0, y1, z0, z1)
    verts = rotate_yz(verts, pivot, -swing)
    all_vertices.extend(verts)

    # Left arm (vertices 24-31) - swings with +sin(t)
    name, x0, x1, y0, y1, z0, z1 = left_arm_def
    pivot = ((x0 + x1) / 2, y1, (z0 + z1) / 2)  # shoulder
    verts = generate_box_vertices(x0, x1, y0, y1, z0, z1)
    verts = rotate_yz(verts, pivot, swing)
    all_vertices.extend(verts)

    # Right leg (vertices 32-39) - swings with +sin(t) (opposite to right arm)
    name, x0, x1, y0, y1, z0, z1 = right_leg_def
    pivot = ((x0 + x1) / 2, y1, (z0 + z1) / 2)  # hip
    verts = generate_box_vertices(x0, x1, y0, y1, z0, z1)
    verts = rotate_yz(verts, pivot, swing)
    all_vertices.extend(verts)

    # Left leg (vertices 40-47) - swings with -sin(t) (opposite to left arm)
    name, x0, x1, y0, y1, z0, z1 = left_leg_def
    pivot = ((x0 + x1) / 2, y1, (z0 + z1) / 2)  # hip
    verts = generate_box_vertices(x0, x1, y0, y1, z0, z1)
    verts = rotate_yz(verts, pivot, -swing)
    all_vertices.extend(verts)

    return all_vertices


def generate_faces():
    """Generate face indices (constant across all frames)."""
    all_faces = []
    face_colors = []

    # Colors: 1=skin, 2=body, 3=legs
    box_colors = [1, 2, 1, 1, 3, 3]  # head, body, r_arm, l_arm, r_leg, l_leg

    for box_idx in range(6):
        base = box_idx * 8
        faces = generate_box_faces(base, flip_winding=False)
        all_faces.extend(faces)
        # Cycle colors per triangle for debugging
        for j in range(12):
            face_colors.append((j % 3) + 1)

    return all_faces, face_colors


def validate_edges(faces):
    """Validate that each edge appears exactly twice in opposite directions."""
    from collections import defaultdict

    edge_count = defaultdict(int)
    for (i, j, k, name) in faces:
        for e in [(i, j), (j, k), (k, i)]:
            edge_count[e] += 1

    errors = []
    for edge, count in edge_count.items():
        a, b = edge
        reverse = (b, a)
        if reverse not in edge_count:
            errors.append(f"Edge ({a},{b}) has no reverse!")
        if count > 1:
            errors.append(f"Edge {edge} appears {count} times!")

    return errors


def to_signed_byte(val):
    """Convert signed float to unsigned byte (two's complement)."""
    val = int(round(val))
    if val < -128:
        val = -128
    if val > 127:
        val = 127
    if val < 0:
        val = 256 + val
    return val & 0xFF


def output_asm():
    """Output as 6502 assembly with animation frames."""

    # Generate all frames
    all_frames = [generate_steve_frame(f) for f in range(NUM_FRAMES)]
    num_vertices = len(all_frames[0])

    # Generate faces (constant)
    faces, colors = generate_faces()

    # Validate
    errors = validate_edges(faces)
    if errors:
        print("; *** EDGE VALIDATION ERRORS ***", file=sys.stderr)
        for e in errors:
            print(f";   {e}", file=sys.stderr)
    else:
        print("; Edge validation passed", file=sys.stderr)

    print("; Minecraft Steve model with walking animation - generated by gen_steve.py")
    print(f"; 6 boxes, {num_vertices} vertices, {len(faces)} triangles, {NUM_FRAMES} animation frames")
    print()
    print(f"STEVE_NUM_VERTICES = {num_vertices}")
    print(f"STEVE_NUM_FACES_0 = {len(faces)}      ; All faces in single mesh")
    print(f"STEVE_NUM_FACES_1 = 0")
    print(f"STEVE_NUM_FRAMES = {NUM_FRAMES}")
    print()

    # Output vertex data for each frame
    for frame in range(NUM_FRAMES):
        vertices = all_frames[frame]

        print(f"steve_vx_{frame}")
        for i in range(0, len(vertices), 8):
            chunk = vertices[i:i+8]
            bytes_str = ", ".join(f"${to_signed_byte(v[0]):02x}" for v in chunk)
            print(f"        .byte {bytes_str}")

        print(f"steve_vy_{frame}")
        for i in range(0, len(vertices), 8):
            chunk = vertices[i:i+8]
            bytes_str = ", ".join(f"${to_signed_byte(v[1]):02x}" for v in chunk)
            print(f"        .byte {bytes_str}")

        print(f"steve_vz_{frame}")
        for i in range(0, len(vertices), 8):
            chunk = vertices[i:i+8]
            bytes_str = ", ".join(f"${to_signed_byte(v[2]):02x}" for v in chunk)
            print(f"        .byte {bytes_str}")
        print()

    # Pointer tables
    print("; Pointer tables for animation frames")
    print("steve_vx_lo")
    for frame in range(NUM_FRAMES):
        print(f"        .byte <steve_vx_{frame}")
    print("steve_vx_hi")
    for frame in range(NUM_FRAMES):
        print(f"        .byte >steve_vx_{frame}")
    print()

    print("steve_vy_lo")
    for frame in range(NUM_FRAMES):
        print(f"        .byte <steve_vy_{frame}")
    print("steve_vy_hi")
    for frame in range(NUM_FRAMES):
        print(f"        .byte >steve_vy_{frame}")
    print()

    print("steve_vz_lo")
    for frame in range(NUM_FRAMES):
        print(f"        .byte <steve_vz_{frame}")
    print("steve_vz_hi")
    for frame in range(NUM_FRAMES):
        print(f"        .byte >steve_vz_{frame}")
    print()

    # Face indices (constant)
    print("; Face indices (constant across all frames)")
    print("steve_fi_0")
    for i in range(0, len(faces), 12):
        chunk = faces[i:i+12]
        bytes_str = ", ".join(f"${f[0]:02x}" for f in chunk)
        print(f"        .byte {bytes_str}")
    print()

    print("steve_fj_0")
    for i in range(0, len(faces), 12):
        chunk = faces[i:i+12]
        bytes_str = ", ".join(f"${f[1]:02x}" for f in chunk)
        print(f"        .byte {bytes_str}")
    print()

    print("steve_fk_0")
    for i in range(0, len(faces), 12):
        chunk = faces[i:i+12]
        bytes_str = ", ".join(f"${f[2]:02x}" for f in chunk)
        print(f"        .byte {bytes_str}")
    print()

    print("; Empty second mesh")
    print("steve_fi_1")
    print("steve_fj_1")
    print("steve_fk_1")
    print()

    # Face colors
    print("; Face colors")
    print("steve_fcol_0")
    for i in range(0, len(colors), 12):
        chunk = colors[i:i+12]
        bytes_str = ", ".join(f"${c:02x}" for c in chunk)
        print(f"        .byte {bytes_str}")
    print()

    print("steve_fcol_1")


if __name__ == "__main__":
    output_asm()
