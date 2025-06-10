package sprite

import "../util"

SpriteId :: enum {
    Ravioli_1,
    Ravioli_2,
    Ravioli_3,
    Ravioli_4,
}

Sprite :: struct {
    atlas_offset: util.Vec2,
    sprite_size:  util.Vec2,
}

Transform :: struct {
    position: util.Vec2,
    scale:    util.Vec2,
    rotation: f32,
}

RenderableSprite :: struct {
    sprite_id: SpriteId,
    transform: Transform,
    color:     util.Vec4,
}

SpriteInstance :: struct {
    x, y, z, rotation:          f32,
    w, h, padding_a, padding_b: f32,
    tex_u, tex_v, tex_w, tex_h: f32,
    r, g, b, a:                 f32,
}

update_sprites :: proc(sprite_data: [^]SpriteInstance, renderable_sprites: []RenderableSprite) {
    for i := 0; i < len(renderable_sprites); i += 1 {
        renderable := renderable_sprites[i]
        sprite := get_sprite(renderable.sprite_id)
        
        sprite_data[i] = SpriteInstance {
            x         = renderable.transform.position.x,
            y         = renderable.transform.position.y,
            z         = 0,
            rotation  = renderable.transform.rotation,
            w         = sprite.sprite_size.x * renderable.transform.scale.x,
            h         = sprite.sprite_size.y * renderable.transform.scale.y,
            tex_u     = sprite.atlas_offset.x,
            tex_v     = sprite.atlas_offset.y,
            tex_w     = sprite.sprite_size.x,
            tex_h     = sprite.sprite_size.y,
            r         = renderable.color.x,
            g         = renderable.color.y,
            b         = renderable.color.z,
            a         = renderable.color.w,
            padding_a = 0,
            padding_b = 0,
        }
    }
}

