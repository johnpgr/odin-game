package util

Vec2 :: distinct [2]f32
Vec3 :: distinct [3]f32
Vec4 :: distinct [4]f32
Mat4x4 :: distinct [4][4]f32

PI :: 3.14159265358979323846

create_orthographic_offcenter :: proc(
    left: f32,
    right: f32,
    bottom: f32,
    top: f32,
    z_near_plane: f32,
    z_far_plane: f32,
) -> Mat4x4 {
    return Mat4x4 {
        {2 / (right - left), 0, 0, 0},
        {0, 2 / (top - bottom), 0, 0},
        {0, 0, 1 / (z_near_plane - z_far_plane), 0},
        {
            (left + right) / (left - right),
            (top + bottom) / (bottom - top),
            z_near_plane / (z_near_plane - z_far_plane),
            1,
        },
    }
}
