// Metal helpers for Nightforge's Vulkan layer (nightforge-vulkan-metalfx.m). Metal objects travel
// as plain pointers, the way VK_EXT_metal_objects hands them out to C.
#pragma once
#include <stdint.h>

/// 2 when the layer's window is on a Retina screen (the main display when that's unknown), else 1.
int nf_display_scale(void *ca_metal_layer);
/// A CAMetalLayer's size in points; 0 when it has none yet.
int nf_layer_size(void *ca_metal_layer, uint32_t *width, uint32_t *height);
/// A MetalFX spatial scaler for this Vulkan format and these sizes; NULL when MetalFX can't do it.
void *nf_scaler_create(void *mtl_device, uint32_t vk_format, uint32_t width, uint32_t height,
                       uint32_t output_width, uint32_t output_height);
void nf_scaler_release(void *scaler);
/// Encodes the upscale of `input` into `output` on the queue and commits it; 0 when it couldn't.
/// `*last` holds the latest command buffer (retained; the previous one is released).
int nf_upscale(void *mtl_command_queue, void *scaler, void *input, void *output, void **last);
/// Waits until a command buffer from nf_upscale has run, then releases it. NULL is fine.
void nf_wait_and_release(void *command_buffer);
/// Keeps an Objective-C object (a CAMetalLayer) alive from C, and lets it go again. NULL is fine.
void *nf_retain(void *object);
void nf_release(void *object);
