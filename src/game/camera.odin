package game

import "../util"

OrthographicCamera2d :: struct {
    zoom:       f32,
    position:   util.Vec2,
    dimensions: util.Vec2,
}

get_projection_matrix :: proc(camera: ^OrthographicCamera2d) -> util.Mat4x4 {
    half_width := camera.dimensions.x / (2 * camera.zoom)
    half_height := camera.dimensions.y / (2 * camera.zoom)

    left := camera.position.x - half_width
    right := camera.position.x + half_width
    bottom := camera.position.y + half_height
    top := camera.position.y - half_height

    return util.create_orthographic_offcenter(left, right, top, bottom, 0, -1)
}
