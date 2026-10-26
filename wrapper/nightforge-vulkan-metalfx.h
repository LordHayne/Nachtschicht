// Metal helpers for Nightforge's Vulkan layer (nightforge-vulkan-metalfx.m). Metal objects travel
// as plain pointers, the way VK_EXT_metal_objects hands them out to C.
#pragma once
#include <stdint.h>

/// 2 on a Retina main display, else 1.
int nf_display_scale(void);
/// A CAMetalLayer's size in points; 0 when it has none yet.
int nf_layer_size(void *ca_metal_layer, uint32_t *width, uint32_t *height);
/// A MetalFX spatial scaler for this Vulkan format and these sizes; NULL when MetalFX can't do it.
void *nf_scaler_create(void *mtl_device, uint32_t vk_format, uint32_t width, uint32_t height,
                       uint32_t output_width, uint32_t output_height);
void nf_scaler_release(void *scaler);
/// Encodes the upscale of `input` into `output` on the queue and commits it; 0 when it couldn't.
int nf_upscale(void *mtl_command_queue, void *scaler, void *input, void *output);
