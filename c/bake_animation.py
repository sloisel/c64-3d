#!/usr/bin/env python3
"""
Bake GLTF skeletal animation to per-frame vertex positions.
Extracts 16 frames and exports as C64-ready assembly data.
"""

import json
import struct
import numpy as np
from pathlib import Path

def load_gltf(gltf_path):
    """Load GLTF file and its binary buffer."""
    with open(gltf_path, 'r') as f:
        gltf = json.load(f)
    bin_path = Path(gltf_path).parent / gltf['buffers'][0]['uri']
    with open(bin_path, 'rb') as f:
        buffer_data = f.read()
    return gltf, buffer_data

def get_accessor_data(gltf, buffer_data, accessor_idx):
    """Extract typed data from a GLTF accessor."""
    accessor = gltf['accessors'][accessor_idx]
    buffer_view = gltf['bufferViews'][accessor['bufferView']]

    offset = buffer_view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
    count = accessor['count']

    COMPONENT_TYPES = {
        5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2),
        5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4),
    }
    TYPE_COUNTS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

    fmt, size = COMPONENT_TYPES[accessor['componentType']]
    num_components = TYPE_COUNTS[accessor['type']]
    stride = buffer_view.get('byteStride', size * num_components)

    data = []
    for i in range(count):
        pos = offset + i * stride
        vals = [struct.unpack_from(fmt, buffer_data, pos + j * size)[0]
                for j in range(num_components)]
        data.append(vals if num_components > 1 else vals[0])

    return np.array(data)

def quat_to_matrix(q):
    """Convert quaternion [x,y,z,w] to 4x4 rotation matrix."""
    x, y, z, w = q
    return np.array([
        [1-2*y*y-2*z*z, 2*x*y-2*w*z, 2*x*z+2*w*y, 0],
        [2*x*y+2*w*z, 1-2*x*x-2*z*z, 2*y*z-2*w*x, 0],
        [2*x*z-2*w*y, 2*y*z+2*w*x, 1-2*x*x-2*y*y, 0],
        [0, 0, 0, 1]
    ])

def translation_matrix(t):
    """Create 4x4 translation matrix."""
    m = np.eye(4)
    m[:3, 3] = t
    return m

def scale_matrix(s):
    """Create 4x4 scale matrix."""
    m = np.eye(4)
    m[0,0], m[1,1], m[2,2] = s
    return m

def get_node_local_matrix(node):
    """Get local transform matrix from node."""
    if 'matrix' in node:
        return np.array(node['matrix']).reshape(4, 4).T

    m = np.eye(4)
    if 'scale' in node:
        m = m @ scale_matrix(node['scale'])
    if 'rotation' in node:
        m = m @ quat_to_matrix(node['rotation'])
    if 'translation' in node:
        m = m @ translation_matrix(node['translation'])
    return m

def interpolate_keyframes(times, values, t, interpolation='LINEAR'):
    """Interpolate animation value at time t."""
    if t <= times[0]:
        return values[0]
    if t >= times[-1]:
        return values[-1]

    # Find surrounding keyframes
    for i in range(len(times) - 1):
        if times[i] <= t <= times[i + 1]:
            alpha = (t - times[i]) / (times[i + 1] - times[i])
            return values[i] * (1 - alpha) + values[i + 1] * alpha

    return values[-1]

def slerp(q1, q2, t):
    """Spherical linear interpolation for quaternions."""
    dot = np.dot(q1, q2)
    if dot < 0:
        q2 = -q2
        dot = -dot

    if dot > 0.9995:
        return q1 * (1 - t) + q2 * t

    theta = np.arccos(np.clip(dot, -1, 1))
    sin_theta = np.sin(theta)
    return (q1 * np.sin((1 - t) * theta) + q2 * np.sin(t * theta)) / sin_theta

def interpolate_rotation(times, values, t):
    """Interpolate quaternion rotation at time t."""
    if t <= times[0]:
        return values[0]
    if t >= times[-1]:
        return values[-1]

    for i in range(len(times) - 1):
        if times[i] <= t <= times[i + 1]:
            alpha = (t - times[i]) / (times[i + 1] - times[i])
            return slerp(values[i], values[i + 1], alpha)

    return values[-1]

def bake_animation(gltf_path, num_frames=16):
    """Bake skeletal animation to vertex positions for each frame."""
    gltf, buffer_data = load_gltf(gltf_path)

    # Get mesh data
    mesh = gltf['meshes'][0]
    primitive = mesh['primitives'][0]

    positions = get_accessor_data(gltf, buffer_data, primitive['attributes']['POSITION'])
    indices = get_accessor_data(gltf, buffer_data, primitive['indices'])
    joints = get_accessor_data(gltf, buffer_data, primitive['attributes']['JOINTS_0'])
    weights = get_accessor_data(gltf, buffer_data, primitive['attributes']['WEIGHTS_0'])

    # Get skin data
    skin = gltf['skins'][0]
    joint_nodes = skin['joints']
    inv_bind_matrices = get_accessor_data(gltf, buffer_data, skin['inverseBindMatrices'])
    inv_bind_matrices = inv_bind_matrices.reshape(-1, 4, 4).transpose(0, 2, 1)

    # Get animation data
    anim = gltf['animations'][0]
    anim_duration = 0

    # Build channel lookup: node_idx -> {path: (times, values)}
    node_anims = {}
    for channel in anim['channels']:
        sampler = anim['samplers'][channel['sampler']]
        target = channel['target']
        node_idx = target['node']
        path = target['path']

        times = get_accessor_data(gltf, buffer_data, sampler['input'])
        values = get_accessor_data(gltf, buffer_data, sampler['output'])

        anim_duration = max(anim_duration, times[-1])

        if node_idx not in node_anims:
            node_anims[node_idx] = {}
        node_anims[node_idx][path] = (times, values)

    print(f"Animation duration: {anim_duration:.2f}s")
    print(f"Baking {num_frames} frames...")

    # Build node hierarchy
    def get_node_parent(node_idx):
        for i, node in enumerate(gltf['nodes']):
            if 'children' in node and node_idx in node['children']:
                return i
        return None

    def get_world_matrix(node_idx, time):
        """Get world transform matrix for a node at given time."""
        node = gltf['nodes'][node_idx]

        # Start with node's base transform
        if node_idx in node_anims:
            # Apply animated transforms
            local = np.eye(4)
            anims = node_anims[node_idx]

            if 'scale' in anims:
                times, values = anims['scale']
                s = interpolate_keyframes(times, values, time)
                local = local @ scale_matrix(s)
            elif 'scale' in node:
                local = local @ scale_matrix(node['scale'])

            if 'rotation' in anims:
                times, values = anims['rotation']
                q = interpolate_rotation(times, values, time)
                local = local @ quat_to_matrix(q)
            elif 'rotation' in node:
                local = local @ quat_to_matrix(node['rotation'])

            if 'translation' in anims:
                times, values = anims['translation']
                t = interpolate_keyframes(times, values, time)
                local = local @ translation_matrix(t)
            elif 'translation' in node:
                local = local @ translation_matrix(node['translation'])
        else:
            local = get_node_local_matrix(node)

        # Apply parent transform
        parent = get_node_parent(node_idx)
        if parent is not None:
            return get_world_matrix(parent, time) @ local
        return local

    # Bake frames
    baked_frames = []

    for frame in range(num_frames):
        t = (frame / num_frames) * anim_duration

        # Compute joint matrices for this frame
        joint_matrices = []
        for i, joint_node in enumerate(joint_nodes):
            world = get_world_matrix(joint_node, t)
            joint_mat = world @ inv_bind_matrices[i]
            joint_matrices.append(joint_mat)

        # Transform each vertex
        frame_positions = []
        for v in range(len(positions)):
            pos = np.append(positions[v], 1.0)  # Homogeneous

            # Weighted sum of joint transforms
            skinned = np.zeros(4)
            for j in range(4):
                joint_idx = int(joints[v][j])
                weight = weights[v][j]
                if weight > 0:
                    skinned += weight * (joint_matrices[joint_idx] @ pos)

            frame_positions.append(skinned[:3])

        baked_frames.append(np.array(frame_positions))
        print(f"  Frame {frame}: t={t:.3f}s")

    return baked_frames, indices

def merge_and_scale(frames, indices, target_size=120):
    """Merge duplicate vertices and scale to target size."""
    # Use first frame to establish vertex mapping
    positions = frames[0]

    # Merge duplicates (same position across all frames)
    tolerance = 0.001
    pos_to_idx = {}
    new_indices_map = {}
    unique_positions = [[] for _ in range(len(frames))]

    for old_idx in range(len(positions)):
        # Check if this vertex matches an existing one (in first frame)
        key = tuple(round(p / tolerance) * tolerance for p in positions[old_idx])

        if key not in pos_to_idx:
            new_idx = len(unique_positions[0])
            pos_to_idx[key] = new_idx
            for f in range(len(frames)):
                unique_positions[f].append(frames[f][old_idx])

        new_indices_map[old_idx] = pos_to_idx[key]

    # Remap face indices
    new_indices = [new_indices_map[int(i)] for i in indices]

    # Convert to numpy
    unique_positions = [np.array(p) for p in unique_positions]

    print(f"After merge: {len(unique_positions[0])} unique vertices")

    # Find global bounding box across all frames
    all_positions = np.concatenate(unique_positions)
    min_pos = all_positions.min(axis=0)
    max_pos = all_positions.max(axis=0)
    center = (min_pos + max_pos) / 2
    max_extent = (max_pos - min_pos).max()
    scale = (target_size * 2) / max_extent

    # Scale all frames
    scaled_frames = []
    for positions in unique_positions:
        scaled = ((positions - center) * scale).astype(int)
        # Clamp to int8 range
        scaled = np.clip(scaled, -127, 127)
        scaled_frames.append(scaled)

    return scaled_frames, new_indices

def export_assembly(frames, indices, output_path):
    """Export baked animation as assembly data."""
    num_frames = len(frames)
    num_vertices = len(frames[0])
    num_faces = len(indices) // 3

    # Split faces into two sub-meshes
    split = num_faces // 2

    with open(output_path, 'w') as f:
        f.write(f'; Baked animation: {num_frames} frames, {num_vertices} vertices, {num_faces} faces\n')
        f.write(f'; Split into {split} + {num_faces - split} faces\n\n')

        f.write(f'GRUNT_NUM_FRAMES = {num_frames}\n')
        f.write(f'GRUNT_NUM_VERTICES = {num_vertices}\n')
        f.write(f'GRUNT_NUM_FACES_0 = {split}\n')
        f.write(f'GRUNT_NUM_FACES_1 = {num_faces - split}\n\n')

        # Vertex data for each frame
        for frame_idx, positions in enumerate(frames):
            f.write(f'; Frame {frame_idx}\n')
            for axis, name in enumerate(['x', 'y', 'z']):
                f.write(f'grunt_v{name}_{frame_idx}\n')
                data = positions[:, axis]
                for i in range(0, len(data), 16):
                    chunk = data[i:i+16]
                    # Convert to unsigned bytes
                    chunk = [(int(x) if x >= 0 else int(x) + 256) for x in chunk]
                    f.write('        .byte ' + ', '.join(f'${x:02x}' for x in chunk) + '\n')
                f.write('\n')

        # Frame pointer tables
        for axis in ['x', 'y', 'z']:
            f.write(f'grunt_v{axis}_lo\n')
            for i in range(num_frames):
                f.write(f'        .byte <grunt_v{axis}_{i}\n')
            f.write(f'\ngrunt_v{axis}_hi\n')
            for i in range(num_frames):
                f.write(f'        .byte >grunt_v{axis}_{i}\n')
            f.write('\n')

        # Face indices (shared across all frames)
        def write_array(name, data):
            f.write(f'{name}\n')
            for i in range(0, len(data), 16):
                chunk = [int(x) for x in data[i:i+16]]
                f.write('        .byte ' + ', '.join(f'${x:02x}' for x in chunk) + '\n')
            f.write('\n')

        write_array('grunt_fi_0', [indices[i*3] for i in range(split)])
        write_array('grunt_fj_0', [indices[i*3+1] for i in range(split)])
        write_array('grunt_fk_0', [indices[i*3+2] for i in range(split)])

        write_array('grunt_fi_1', [indices[i*3] for i in range(split, num_faces)])
        write_array('grunt_fj_1', [indices[i*3+1] for i in range(split, num_faces)])
        write_array('grunt_fk_1', [indices[i*3+2] for i in range(split, num_faces)])

        # Face colors
        fcol0 = [(1 + (i % 3)) for i in range(split)]
        fcol1 = [(1 + (i % 3)) for i in range(split, num_faces)]
        write_array('grunt_fcol_0', fcol0)
        write_array('grunt_fcol_1', fcol1)

    print(f"Exported to {output_path}")

def main():
    gltf_path = "../classic_quake_grunt_zombie_scream/scene.gltf"

    print("Baking animation...")
    frames, indices = bake_animation(gltf_path, num_frames=24)

    print("\nMerging vertices and scaling...")
    scaled_frames, merged_indices = merge_and_scale(frames, indices)

    print("\nExporting assembly...")
    export_assembly(scaled_frames, merged_indices, "../asm/grunt_anim.asm")

    print("\nDone!")

if __name__ == "__main__":
    main()
