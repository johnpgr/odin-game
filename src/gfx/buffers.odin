package gfx

import "../sprite"
import "core:fmt"
import sdl "vendor:sdl3"

SPRITE_COUNT :: 1024

SpriteBuffers :: struct {
	transfer_buffer: ^sdl.GPUTransferBuffer,
	storage_buffer:  ^sdl.GPUBuffer,
}

SpriteBuffersError :: enum {
	FailedToCreateTransferBuffer,
	FailedToCreateStorageBuffer,
	FailedToAcquireCommandBuffer,
	FailedToBeginCopyPass,
}

create_sprite_buffers :: proc(device: ^sdl.GPUDevice) -> (SpriteBuffers, SpriteBuffersError) {
	sprite_transfer_buffer := sdl.CreateGPUTransferBuffer(
		device,
		sdl.GPUTransferBufferCreateInfo {
			usage = .UPLOAD,
			size = SPRITE_COUNT * size_of(sprite.SpriteInstance),
		},
	)
	if sprite_transfer_buffer == nil {
		sdl.Log("Failed to create GPU transfer buffer for sprite instances")
		return {}, .FailedToCreateTransferBuffer
	}

	sprite_buffer := sdl.CreateGPUBuffer(
		device,
		sdl.GPUBufferCreateInfo {
			usage = {.GRAPHICS_STORAGE_READ},
			size = SPRITE_COUNT * size_of(sprite.SpriteInstance),
		},
	)
	if sprite_buffer == nil {
		sdl.Log("Failed to create GPU buffer for sprite instances")
		sdl.ReleaseGPUTransferBuffer(device, sprite_transfer_buffer)
		return {}, .FailedToCreateStorageBuffer
	}

	return {transfer_buffer = sprite_transfer_buffer, storage_buffer = sprite_buffer}, nil
}

update_sprites :: proc(
	sprite_data: [^]sprite.SpriteInstance,
	renderable_sprites: []sprite.RenderableSprite,
) {
	for i := 0; i < len(renderable_sprites); i += 1 {
		renderable := renderable_sprites[i]
		s := sprite.get_sprite(renderable.sprite_id)

		sprite_data[i] = sprite.SpriteInstance {
			x         = renderable.transform.position.x,
			y         = renderable.transform.position.y,
			z         = 0,
			rotation  = renderable.transform.rotation,
			w         = s.sprite_size.x * renderable.transform.scale.x,
			h         = s.sprite_size.y * renderable.transform.scale.y,
			tex_u     = s.atlas_offset.x,
			tex_v     = s.atlas_offset.y,
			tex_w     = s.sprite_size.x,
			tex_h     = s.sprite_size.y,
			r         = renderable.color.x,
			g         = renderable.color.y,
			b         = renderable.color.z,
			a         = renderable.color.w,
			padding_a = 0,
			padding_b = 0,
		}
	}
}

upload_sprite_data :: proc(
	device: ^sdl.GPUDevice,
	cmd_buf: ^sdl.GPUCommandBuffer,
	buffers: SpriteBuffers,
	renderable_sprites: [dynamic]sprite.RenderableSprite,
) -> bool {
	raw_ptr := sdl.MapGPUTransferBuffer(device, buffers.transfer_buffer, true)
	if raw_ptr == nil {
		sdl.Log("Failed to map sprite transfer buffer for upload")
		return false
	}

    sprite_data_ptr := cast([^]sprite.SpriteInstance)raw_ptr
	update_sprites(sprite_data_ptr, renderable_sprites[:])

	sdl.UnmapGPUTransferBuffer(device, buffers.transfer_buffer)

	copy_pass := sdl.BeginGPUCopyPass(cmd_buf)
	if copy_pass == nil {
		sdl.Log("Failed to begin GPU copy pass for sprite data upload")
		return false
	}

	sdl.UploadToGPUBuffer(
		copy_pass,
		sdl.GPUTransferBufferLocation{transfer_buffer = buffers.transfer_buffer, offset = 0},
		sdl.GPUBufferRegion {
			buffer = buffers.storage_buffer,
			offset = 0,
			size = SPRITE_COUNT * size_of(sprite.SpriteInstance),
		},
		true,
	)

	sdl.EndGPUCopyPass(copy_pass)
	return true
}
