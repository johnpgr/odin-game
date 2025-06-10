#+feature dynamic-literals
package sprite

SPRITE_ATLAS := map[SpriteId]Sprite {
    .Ravioli_1 = {atlas_offset = {0.0, 0.0}, sprite_size = {0.5, 0.5}},
    .Ravioli_2 = {atlas_offset = {0.5, 0.0}, sprite_size = {0.5, 0.5}},
    .Ravioli_3 = {atlas_offset = {0.0, 0.5}, sprite_size = {0.5, 0.5}},
    .Ravioli_4 = {atlas_offset = {0.5, 0.5}, sprite_size = {0.5, 0.5}},
}

get_sprite :: proc(id: SpriteId) -> Sprite {
    return SPRITE_ATLAS[id]
}
