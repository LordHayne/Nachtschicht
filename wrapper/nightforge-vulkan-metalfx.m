// The Metal side of Nightforge's Vulkan layer (nightforge-vulkan-layer.c): MetalFX spatial upscaling
// of a game's frame to the window's Retina pixels. Plain C functions over Metal objects, which the
// layer gets from MoltenVK through VK_EXT_metal_objects. Built with -fobjc-arc.
// They run on the game's render thread, a Wine thread without an autorelease pool: each one drains
// its own, or Metal's autoreleased objects would pile up with every frame.

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Metal/Metal.h>
#import <MetalFX/MetalFX.h>
#import <QuartzCore/QuartzCore.h>
#include <vulkan/vulkan_core.h>

#include "nightforge-vulkan-metalfx.h"

/// Picture formats MetalFX takes that games use for their swapchains.
static MTLPixelFormat metal_format(uint32_t vk_format) {
    switch (vk_format) {
    case VK_FORMAT_B8G8R8A8_UNORM: return MTLPixelFormatBGRA8Unorm;
    case VK_FORMAT_B8G8R8A8_SRGB: return MTLPixelFormatBGRA8Unorm_sRGB;
    case VK_FORMAT_R8G8B8A8_UNORM: return MTLPixelFormatRGBA8Unorm;
    case VK_FORMAT_R8G8B8A8_SRGB: return MTLPixelFormatRGBA8Unorm_sRGB;
    case VK_FORMAT_A2B10G10R10_UNORM_PACK32: return MTLPixelFormatRGB10A2Unorm;
    default: return MTLPixelFormatInvalid;
    }
}

int nf_display_scale(void *ca_metal_layer) {
    @autoreleasepool {
        // The screen the game's window is on (an external TV may differ from the built-in display),
        // through the view Wine made the layer for; the main display when that isn't known.
        CAMetalLayer *layer = (__bridge CAMetalLayer *)ca_metal_layer;
        id delegate = layer.delegate;
        NSScreen *screen = [delegate isKindOfClass:[NSView class]] ? ((NSView *)delegate).window.screen : nil;
        if (screen) return screen.backingScaleFactor >= 2 ? 2 : 1;
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(CGMainDisplayID());
        if (!mode) return 1;
        size_t points = CGDisplayModeGetWidth(mode), pixels = CGDisplayModeGetPixelWidth(mode);
        CGDisplayModeRelease(mode);
        return points && pixels >= points * 2 ? 2 : 1;
    }
}

int nf_layer_size(void *ca_metal_layer, uint32_t *width, uint32_t *height) {
    if (!ca_metal_layer) return 0;
    @autoreleasepool {
        CAMetalLayer *layer = (__bridge CAMetalLayer *)ca_metal_layer;
        CGSize size = layer.bounds.size;
        if (size.width < 1 || size.height < 1) return 0;
        *width = (uint32_t)size.width;
        *height = (uint32_t)size.height;
        return 1;
    }
}

void *nf_retain(void *object) {
    return object ? (__bridge_retained void *)(__bridge id)object : NULL;
}

void nf_release(void *object) {
    if (object) (void)(__bridge_transfer id)object;
}

void *nf_scaler_create(void *mtl_device, uint32_t vk_format, uint32_t width, uint32_t height,
                       uint32_t output_width, uint32_t output_height) {
    if (@available(macOS 13.0, *)) @autoreleasepool {
        id<MTLDevice> device = (__bridge id<MTLDevice>)mtl_device;
        MTLPixelFormat format = metal_format(vk_format);
        if (!device || format == MTLPixelFormatInvalid || ![MTLFXSpatialScalerDescriptor supportsDevice:device]) return NULL;
        MTLFXSpatialScalerDescriptor *descriptor = [MTLFXSpatialScalerDescriptor new];
        descriptor.inputWidth = width;
        descriptor.inputHeight = height;
        descriptor.outputWidth = output_width;
        descriptor.outputHeight = output_height;
        descriptor.colorTextureFormat = format;
        descriptor.outputTextureFormat = format;
        // Games hand over finished, display-ready pictures.
        descriptor.colorProcessingMode = MTLFXSpatialScalerColorProcessingModePerceptual;
        id<MTLFXSpatialScaler> scaler = [descriptor newSpatialScalerWithDevice:device];
        return scaler ? (__bridge_retained void *)scaler : NULL;
    }
    return NULL;
}

void nf_scaler_release(void *scaler) {
    nf_release(scaler);
}

int nf_upscale(void *mtl_command_queue, void *scaler, void *input, void *output, void **last) {
    if (@available(macOS 13.0, *)) @autoreleasepool {
        id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)mtl_command_queue;
        id<MTLFXSpatialScaler> fx = (__bridge id<MTLFXSpatialScaler>)scaler;
        id<MTLTexture> color = (__bridge id<MTLTexture>)input, target = (__bridge id<MTLTexture>)output;
        if (!queue || !fx || !color || !target) return 0;
        // The drawable must be one MetalFX can write to (the layer asks MoltenVK for that).
        if ((target.usage & fx.outputTextureUsage) != fx.outputTextureUsage) return 0;
        id<MTLCommandBuffer> commands = [queue commandBuffer];
        if (!commands) return 0;
        fx.colorTexture = color;
        fx.outputTexture = target;
        fx.inputContentWidth = color.width;
        fx.inputContentHeight = color.height;
        [fx encodeToCommandBuffer:commands];
        [commands commit];
        // Kept until the next frame, so tearing the swapchain down waits for this one only.
        nf_release(*last);
        *last = (__bridge_retained void *)commands;
        return 1;
    }
    return 0;
}

void nf_wait_and_release(void *command_buffer) {
    if (!command_buffer) return;
    @autoreleasepool {
        [(__bridge id<MTLCommandBuffer>)command_buffer waitUntilCompleted];
    }
    nf_release(command_buffer);
}
