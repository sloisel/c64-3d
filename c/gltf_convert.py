#!/usr/bin/env python3
"""
Convert GLTF model to simple mesh format for C64 rasterizer testing.
Extracts vertices and faces, merges duplicate vertices, and scales to fit.
"""

import json
import struct
import sys
import os
from collections import defaultdict

def load_gltf(gltf_path):
    """Load GLTF file and its binary buffer."""
    with open(gltf_path, 'r') as f:
        gltf = json.load(f)

    # Load binary buffer
    bin_path = os.path.join(os.path.dirname(gltf_path), gltf['buffers'][0]['uri'])
    with open(bin_path, 'rb') as f:
        buffer_data = f.read()

    return gltf, buffer_data

def get_accessor_data(gltf, buffer_data, accessor_idx):
    """Extract data from a GLTF accessor."""
    accessor = gltf['accessors'][accessor_idx]
    buffer_view = gltf['bufferViews'][accessor['bufferView']]

    offset = buffer_view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    count = accessor['count']

    # Component types
    COMPONENT_TYPES = {
        5120: ('b', 1),  # BYTE
        5121: ('B', 1),  # UNSIGNED_BYTE
        5122: ('h', 2),  # SHORT
        5123: ('H', 2),  # UNSIGNED_SHORT
        5125: ('I', 4),  # UNSIGNED_INT
        5126: ('f', 4),  # FLOAT
    }

    # Type to component count
    TYPE_COUNTS = {
        'SCALAR': 1,
        'VEC2': 2,
        'VEC3': 3,
        'VEC4': 4,
    }

    fmt, size = COMPONENT_TYPES[accessor['componentType']]
    num_components = TYPE_COUNTS[accessor['type']]
    stride = buffer_view.get('byteStride', size * num_components)

    data = []
    for i in range(count):
        pos = offset + i * stride
        if num_components == 1:
            val = struct.unpack_from(fmt, buffer_data, pos)[0]
            data.append(val)
        else:
            vals = []
            for j in range(num_components):
                val = struct.unpack_from(fmt, buffer_data, pos + j * size)[0]
                vals.append(val)
            data.append(tuple(vals))

    return data

def merge_vertices(positions, indices, tolerance=0.001):
    """Merge vertices that are close together, return new positions and remapped indices."""
    # Round positions to merge similar ones
    pos_to_idx = {}
    new_positions = []
    index_map = {}

    for old_idx, pos in enumerate(positions):
        # Quantize position
        key = tuple(round(p / tolerance) * tolerance for p in pos)

        if key not in pos_to_idx:
            new_idx = len(new_positions)
            pos_to_idx[key] = new_idx
            new_positions.append(pos)

        index_map[old_idx] = pos_to_idx[key]

    # Remap indices
    new_indices = [index_map[i] for i in indices]

    return new_positions, new_indices

def analyze_mesh(gltf, buffer_data):
    """Extract and analyze mesh data."""
    # Find the mesh primitive
    mesh = gltf['meshes'][0]
    primitive = mesh['primitives'][0]

    # Get positions
    pos_accessor = primitive['attributes']['POSITION']
    positions = get_accessor_data(gltf, buffer_data, pos_accessor)

    # Get indices
    idx_accessor = primitive['indices']
    indices = get_accessor_data(gltf, buffer_data, idx_accessor)

    print(f"Original: {len(positions)} vertices, {len(indices)} indices ({len(indices)//3} triangles)")

    # Find bounding box
    min_pos = [min(p[i] for p in positions) for i in range(3)]
    max_pos = [max(p[i] for p in positions) for i in range(3)]
    print(f"Bounding box: ({min_pos[0]:.2f}, {min_pos[1]:.2f}, {min_pos[2]:.2f}) to ({max_pos[0]:.2f}, {max_pos[1]:.2f}, {max_pos[2]:.2f})")

    # Merge duplicate vertices
    merged_positions, merged_indices = merge_vertices(positions, indices)
    print(f"After merge: {len(merged_positions)} unique vertices, {len(merged_indices)//3} triangles")

    return merged_positions, merged_indices

def scale_and_center(positions, target_size=120):
    """Scale and center mesh to fit in target_size cube centered at origin.

    Also reorients from GLTF convention (Y-up, facing -Z) to our convention:
    - GLTF X -> our X (left/right)
    - GLTF -Y -> our Y (screen Y increases downward)
    - GLTF Z -> our Z (depth, positive = into screen)
    """
    # Find bounding box
    min_pos = [min(p[i] for p in positions) for i in range(3)]
    max_pos = [max(p[i] for p in positions) for i in range(3)]

    # Center
    center = [(min_pos[i] + max_pos[i]) / 2 for i in range(3)]

    # Scale uniformly to fit in [-target_size, +target_size]
    max_extent = max(max_pos[i] - min_pos[i] for i in range(3))
    scale = (target_size * 2) / max_extent if max_extent > 0 else 1

    scaled = []
    for pos in positions:
        # Center and scale
        x = (pos[0] - center[0]) * scale
        y = (pos[1] - center[1]) * scale
        z = (pos[2] - center[2]) * scale
        # Keep original orientation - the renderer handles Y flip in projection
        scaled.append((int(x), int(y), int(z)))

    return scaled

def export_c_header(positions, indices, output_path):
    """Export mesh as C header file."""
    num_vertices = len(positions)
    num_faces = len(indices) // 3

    with open(output_path, 'w') as f:
        f.write(f"// Generated mesh: {num_vertices} vertices, {num_faces} faces\n\n")
        f.write(f"#define GRUNT_NUM_VERTICES {num_vertices}\n")
        f.write(f"#define GRUNT_NUM_FACES {num_faces}\n\n")

        f.write("static int8_t grunt_vertices_x[] = {\n    ")
        f.write(", ".join(str(p[0]) for p in positions))
        f.write("\n};\n\n")

        f.write("static int8_t grunt_vertices_y[] = {\n    ")
        f.write(", ".join(str(p[1]) for p in positions))
        f.write("\n};\n\n")

        f.write("static int8_t grunt_vertices_z[] = {\n    ")
        f.write(", ".join(str(p[2]) for p in positions))
        f.write("\n};\n\n")

        # Faces (indices into vertex arrays)
        f.write("static uint8_t grunt_faces_i[] = {\n    ")
        f.write(", ".join(str(indices[i*3]) for i in range(num_faces)))
        f.write("\n};\n\n")

        f.write("static uint8_t grunt_faces_j[] = {\n    ")
        f.write(", ".join(str(indices[i*3+1]) for i in range(num_faces)))
        f.write("\n};\n\n")

        f.write("static uint8_t grunt_faces_k[] = {\n    ")
        f.write(", ".join(str(indices[i*3+2]) for i in range(num_faces)))
        f.write("\n};\n\n")

def main():
    if len(sys.argv) < 2:
        gltf_path = "../classic_quake_grunt_zombie_scream/scene.gltf"
    else:
        gltf_path = sys.argv[1]

    print(f"Loading {gltf_path}...")
    gltf, buffer_data = load_gltf(gltf_path)

    positions, indices = analyze_mesh(gltf, buffer_data)

    # Check limits
    num_vertices = len(positions)
    num_faces = len(indices) // 3

    if num_vertices > 256:
        print(f"\nWARNING: {num_vertices} vertices exceeds 256 limit!")
        print("Need to find a simpler model or decimate this one.")
        return 1

    if num_faces > 512:
        print(f"\nWARNING: {num_faces} faces exceeds 512 limit!")
        return 1

    # Scale to fit
    scaled_positions = scale_and_center(positions, target_size=100)

    # Check scaled values fit in int8
    for i, p in enumerate(scaled_positions):
        for j, v in enumerate(p):
            if v < -127 or v > 127:
                print(f"WARNING: vertex {i} coord {j} = {v} out of int8 range")

    # Export
    output_path = "grunt_mesh.h"
    export_c_header(scaled_positions, indices, output_path)
    print(f"\nExported to {output_path}")

    return 0

if __name__ == "__main__":
    sys.exit(main())
