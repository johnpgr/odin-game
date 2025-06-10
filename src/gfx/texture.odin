package gfx

import "../util"
import "core:fmt"
import sdl "vendor:sdl3"

TextureResult :: struct {
	texture: ^sdl.GPUTexture,
	sampler: ^sdl.GPUSampler,
}

TextureAndSamplerError :: enum {
	FailedToLoadImage,
	FailedToCreateTexture,
	FailedToCreateSampler,
	FailedToAcquireCommandBuffer,
	FailedToBeginCopyPass,
}

create_texture_and_sampler :: proc(
	device: ^sdl.GPUDevice,
) -> (
	TextureResult,
	TextureAndSamplerError,
) {
	image_data, image_err := util.load_image("ravioli_atlas.bmp")
	if image_err != nil {
		sdl.Log("Failed to load image: %s", image_err)
		return {}, .FailedToLoadImage
	}
	defer sdl.DestroySurface(image_data)

	texture_transfer_buffer := sdl.CreateGPUTransferBuffer(
		device,
		sdl.GPUTransferBufferCreateInfo {
			usage = .UPLOAD,
			size = u32(image_data.pitch * image_data.h),
		},
	)
	if texture_transfer_buffer == nil {
		sdl.Log("Failed to create GPU transfer buffer for texture")
		return {}, .FailedToCreateTexture
	}
	defer sdl.ReleaseGPUTransferBuffer(device, texture_transfer_buffer)

	texture_transfer_ptr := sdl.MapGPUTransferBuffer(device, texture_transfer_buffer, false)
	if texture_transfer_ptr == nil {
		sdl.Log("Failed to map GPU transfer buffer for texture")
		return {}, .FailedToCreateTexture
	}

	_ = sdl.memcpy(texture_transfer_ptr, image_data.pixels, uint(image_data.w * image_data.h * 4))
	sdl.UnmapGPUTransferBuffer(device, texture_transfer_buffer)

	texture := sdl.CreateGPUTexture(
		device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8B8A8_UNORM,
			width = u32(image_data.w),
			height = u32(image_data.h),
			layer_count_or_depth = 1,
			num_levels = 1,
			usage = sdl.GPUTextureUsageFlags{.SAMPLER},
		},
	)

	if texture == nil {
		sdl.Log("Failed to create GPU texture: %s", sdl.GetError())
		return {}, .FailedToCreateTexture
	}

	sampler := sdl.CreateGPUSampler(
		device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			mipmap_mode = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		},
	)
	if sampler == nil {
		sdl.Log("Failed to create GPU sampler: %s", sdl.GetError())
		sdl.ReleaseGPUTexture(device, texture)
		return {}, .FailedToCreateSampler
	}

	upload_cmd_buf := sdl.AcquireGPUCommandBuffer(device)
	if upload_cmd_buf == nil {
		sdl.Log("Failed to acquire GPU command buffer for texture upload")
		sdl.ReleaseGPUSampler(device, sampler)
		sdl.ReleaseGPUTexture(device, texture)
		return {}, .FailedToAcquireCommandBuffer
	}

	copy_pass := sdl.BeginGPUCopyPass(upload_cmd_buf)
	if copy_pass == nil {
		sdl.Log("Failed to begin GPU copy pass for texture")
		sdl.ReleaseGPUSampler(device, sampler)
		sdl.ReleaseGPUTexture(device, texture)
		return {}, .FailedToBeginCopyPass
	}

	sdl.UploadToGPUTexture(
		copy_pass,
		sdl.GPUTextureTransferInfo{transfer_buffer = texture_transfer_buffer, offset = 0},
		sdl.GPUTextureRegion {
			texture = texture,
			w = u32(image_data.w),
			h = u32(image_data.h),
			d = 1,
		},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)
	_ = sdl.SubmitGPUCommandBuffer(upload_cmd_buf)

	return {texture = texture, sampler = sampler}, nil
}
