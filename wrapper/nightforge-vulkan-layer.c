// Lets Windows games that render with Vulkan themselves start on MoltenVK.
//
// Wine hands a game's Vulkan calls to MoltenVK, which turns them into Metal. A few things Metal
// can't do make games give up before they draw anything: they enable a feature MoltenVK lacks
// (No Man's Sky asks for wide lines) and vkCreateDevice fails, or they find a limit too low
// (MoltenVK reports 16 samplers per shader stage, while Metal's argument buffers, which MoltenVK
// uses on Apple silicon, hold far more). This layer sits between Wine and MoltenVK and
//   - reports wide lines as supported (Metal draws them one pixel wide) and leaves out every
//     feature the device doesn't have when the game creates its device, and
//   - reports at least 32 samplers per shader stage (enough for No Man's Sky, which refuses 16),
//     or what a game's profile asks for, and
//   - offers the game only standard (sRGB) picture formats unless the player turned HDR on for it:
//     on a Mac's XDR display games otherwise pick HDR, which under Wine mostly looks washed out, and
//   - with MetalFX on for the game, upscales its picture to the window's Retina pixels. Wine sizes a
//     game's swapchain to the window in points (half the Retina pixels), so the game keeps drawing
//     at that size, into images of the layer's own, while the real swapchain gets the Retina size;
//     at each present MetalFX (nightforge-vulkan-metalfx.m) scales one into the other on the same
//     Metal queue, just before MoltenVK presents. Should MetalFX turn the drawable down, the game is
//     told to recreate its swapchain, which then is the plain one.
// Per-game settings come from nightforge-vulkan.conf next to the game's program (written by
// Nightforge before each start, like dxmt.conf):
//         maxPerStageDescriptorSamplers = 64
//         hdr = on
//         upscale = on
// Each swapchain's size, format and colour space goes to stderr, i.e. Nightforge's wine.log, and
// so does the frame rate: every 10 s for the first two minutes, then every minute. Nightforge learns
// from it which frame limit the game holds (FramePacing.swift).
//
// Inside the "Nightforge Game" bundle the Vulkan loader finds it as an implicit layer in
// Contents/Resources/vulkan/implicit_layer.d (see Engine.installVulkanLayer).
//
// Build (x86_64, like Wine): clang -arch x86_64 -dynamiclib -fvisibility=hidden -fobjc-arc
//     -I vulkan-headers -framework Metal -framework MetalFX -framework QuartzCore -framework CoreGraphics
//     -o nightforge-vulkan-layer.dylib nightforge-vulkan-layer.c nightforge-vulkan-metalfx.m

#include <crt_externs.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vk_layer.h>
#include <vulkan/vulkan_metal.h>

#include "nightforge-vulkan-metalfx.h"

#define EXPORT __attribute__((visibility("default")))

static PFN_vkGetInstanceProcAddr next_instance_proc;
static VkInstance first_instance;
static PFN_vkGetDeviceProcAddr next_device_proc;
static PFN_vkGetPhysicalDeviceFeatures next_features;
static PFN_vkGetPhysicalDeviceFeatures2 next_features2;
static PFN_vkGetPhysicalDeviceProperties next_properties;
static PFN_vkGetPhysicalDeviceProperties2 next_properties2;
static PFN_vkGetPhysicalDeviceSurfaceFormatsKHR next_surface_formats;
static PFN_vkGetPhysicalDeviceSurfaceFormats2KHR next_surface_formats2;
static PFN_vkCreateSwapchainKHR next_create_swapchain;
static PFN_vkQueuePresentKHR next_queue_present;
static PFN_vkCreateMetalSurfaceEXT next_create_metal_surface;
static PFN_vkDestroySwapchainKHR next_destroy_swapchain;
static PFN_vkGetSwapchainImagesKHR next_get_swapchain_images;

// MARK: - Configuration

static uint32_t min_samplers = 32;
static int allow_hdr = 0;
static int allow_upscale = 0;

static int read_config(const char *path) {
    FILE *file = fopen(path, "r");
    if (!file) return 0;
    char line[256];
    while (fgets(line, sizeof line, file)) {
        unsigned value;
        char word[16];
        if (sscanf(line, " maxPerStageDescriptorSamplers = %u", &value) == 1) min_samplers = value;
        if (sscanf(line, " hdr = %15s", word) == 1) allow_hdr = !strcmp(word, "on");
        if (sscanf(line, " upscale = %15s", word) == 1) allow_upscale = !strcmp(word, "on");
    }
    fclose(file);
    return 1;
}

// Wine rewrites argv[0] to the Windows path of the program it runs ("C:\...\Game.exe"); the
// drive maps to $WINEPREFIX/dosdevices/c:.
static int config_next_to_program(char *path, size_t size) {
    char **argv = *_NSGetArgv();
    const char *prefix = getenv("WINEPREFIX");
    if (!argv || !argv[0] || !prefix || strlen(argv[0]) < 3 || argv[0][1] != ':') return 0;
    int length = snprintf(path, size, "%s/dosdevices/%c:%s", prefix, argv[0][0] | 0x20, argv[0] + 2);
    if (length < 0 || (size_t)length >= size) return 0;
    for (char *c = path; *c; c++) if (*c == '\\') *c = '/';
    char *slash = strrchr(path, '/');
    if (!slash || (size_t)(slash - path) + sizeof "/nightforge-vulkan.conf" > size) return 0;
    strcpy(slash, "/nightforge-vulkan.conf");
    return 1;
}

static void load_config(void) {
    char path[PATH_MAX];
    if (config_next_to_program(path, sizeof path) && read_config(path)) return;
    read_config("nightforge-vulkan.conf");  // the working folder, which Steam sets to the game's
}

static pthread_once_t config_once = PTHREAD_ONCE_INIT;

// MARK: - Features and limits the game sees

static VKAPI_ATTR void VKAPI_CALL GetPhysicalDeviceFeatures(VkPhysicalDevice device, VkPhysicalDeviceFeatures *features) {
    next_features(device, features);
    features->wideLines = VK_TRUE;
}

static VKAPI_ATTR void VKAPI_CALL GetPhysicalDeviceFeatures2(VkPhysicalDevice device, VkPhysicalDeviceFeatures2 *features) {
    next_features2(device, features);
    features->features.wideLines = VK_TRUE;
}

static void raise_limits(VkPhysicalDeviceLimits *limits) {
    pthread_once(&config_once, load_config);
    if (limits->maxPerStageDescriptorSamplers < min_samplers) limits->maxPerStageDescriptorSamplers = min_samplers;
}

static VKAPI_ATTR void VKAPI_CALL GetPhysicalDeviceProperties(VkPhysicalDevice device, VkPhysicalDeviceProperties *properties) {
    next_properties(device, properties);
    raise_limits(&properties->limits);
}

static VKAPI_ATTR void VKAPI_CALL GetPhysicalDeviceProperties2(VkPhysicalDevice device, VkPhysicalDeviceProperties2 *properties) {
    next_properties2(device, properties);
    raise_limits(&properties->properties.limits);
}

// MARK: - Picture formats

/// Standard dynamic range: what a game gets unless HDR is on for it.
static int is_sdr(VkColorSpaceKHR space) { return space == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR; }

/// Hands out `kept` entries the Vulkan way: only the count without an array, VK_INCOMPLETE when
/// the game's array is smaller.
static VkResult hand_out(uint32_t kept, uint32_t *count, int has_array) {
    if (!has_array) {
        *count = kept;
        return VK_SUCCESS;
    }
    VkResult result = *count < kept ? VK_INCOMPLETE : VK_SUCCESS;
    if (*count > kept) *count = kept;
    return result;
}

static VKAPI_ATTR VkResult VKAPI_CALL GetPhysicalDeviceSurfaceFormatsKHR(VkPhysicalDevice device, VkSurfaceKHR surface,
                                                                        uint32_t *count, VkSurfaceFormatKHR *formats) {
    pthread_once(&config_once, load_config);
    if (allow_hdr) return next_surface_formats(device, surface, count, formats);
    uint32_t total = 0;
    VkResult result = next_surface_formats(device, surface, &total, NULL);
    if (result != VK_SUCCESS || total == 0) return result == VK_SUCCESS ? hand_out(0, count, formats != NULL) : result;
    VkSurfaceFormatKHR *all = calloc(total, sizeof *all);
    if (!all) return VK_ERROR_OUT_OF_HOST_MEMORY;
    result = next_surface_formats(device, surface, &total, all);
    if (result < 0) {
        free(all);
        return result;
    }
    uint32_t kept = 0;
    for (uint32_t i = 0; i < total; i++) if (is_sdr(all[i].colorSpace)) all[kept++] = all[i];
    if (kept == 0) {
        free(all);
        return next_surface_formats(device, surface, count, formats);  // no sRGB at all: leave the list alone
    }
    if (formats) memcpy(formats, all, (*count < kept ? *count : kept) * sizeof *all);
    free(all);
    return hand_out(kept, count, formats != NULL);
}

static VKAPI_ATTR VkResult VKAPI_CALL GetPhysicalDeviceSurfaceFormats2KHR(VkPhysicalDevice device,
                                                                         const VkPhysicalDeviceSurfaceInfo2KHR *info,
                                                                         uint32_t *count, VkSurfaceFormat2KHR *formats) {
    pthread_once(&config_once, load_config);
    if (allow_hdr) return next_surface_formats2(device, info, count, formats);
    uint32_t total = 0;
    VkResult result = next_surface_formats2(device, info, &total, NULL);
    if (result != VK_SUCCESS || total == 0) return result == VK_SUCCESS ? hand_out(0, count, formats != NULL) : result;
    VkSurfaceFormat2KHR *all = calloc(total, sizeof *all);
    if (!all) return VK_ERROR_OUT_OF_HOST_MEMORY;
    for (uint32_t i = 0; i < total; i++) all[i].sType = VK_STRUCTURE_TYPE_SURFACE_FORMAT_2_KHR;
    result = next_surface_formats2(device, info, &total, all);
    if (result < 0) {
        free(all);
        return result;
    }
    uint32_t kept = 0;
    for (uint32_t i = 0; i < total; i++) if (is_sdr(all[i].surfaceFormat.colorSpace)) all[kept++] = all[i];
    if (kept == 0) {
        free(all);
        return next_surface_formats2(device, info, count, formats);  // no sRGB at all: leave the list alone
    }
    // The game's entries keep their own sType and pNext; only the format itself is filled in.
    if (formats) for (uint32_t i = 0; i < *count && i < kept; i++) formats[i].surfaceFormat = all[i].surfaceFormat;
    free(all);
    return hand_out(kept, count, formats != NULL);
}

// MARK: - MetalFX upscaling

/// What upscaling needs from the device, filled in by CreateDevice when it's on.
static struct {
    VkDevice device;
    void *mtl_device;
    VkPhysicalDeviceMemoryProperties memory;
    PFN_vkExportMetalObjectsEXT export_objects;
    PFN_vkQueueSubmit queue_submit;
    PFN_vkCreateImage create_image;
    PFN_vkDestroyImage destroy_image;
    PFN_vkGetImageMemoryRequirements image_requirements;
    PFN_vkAllocateMemory allocate;
    PFN_vkFreeMemory free_memory;
    PFN_vkBindImageMemory bind;
    PFN_vkDeviceWaitIdle wait_idle;
} metal;

/// MetalFX turned a drawable down once: the swapchains after that are plain ones.
static int upscale_failed;

#define MAX_IMAGES 8

/// A swapchain the layer upscales: the game draws into `images` at `size`, the real swapchain
/// images (`real`) have `target`.
struct upscaled {
    VkSwapchainKHR handle;
    uint32_t count;
    VkImage images[MAX_IMAGES];
    VkDeviceMemory memory[MAX_IMAGES];
    void *textures[MAX_IMAGES];
    VkImage real[MAX_IMAGES];
    VkExtent2D size, target;
    void *scaler;
    int broken;
    struct upscaled *next;
};

static struct upscaled *upscaled_list;
static pthread_mutex_t upscaled_lock = PTHREAD_MUTEX_INITIALIZER;

static struct upscaled *find_upscaled(VkSwapchainKHR handle) {
    for (struct upscaled *u = upscaled_list; u; u = u->next)
        if (u->handle == handle) return u;
    return NULL;
}

/// The CAMetalLayers behind the game's surfaces (Wine creates them with vkCreateMetalSurfaceEXT).
static struct { VkSurfaceKHR surface; void *layer; } surfaces[16];

static VKAPI_ATTR VkResult VKAPI_CALL CreateMetalSurfaceEXT(VkInstance instance, const VkMetalSurfaceCreateInfoEXT *info,
                                                            const VkAllocationCallbacks *allocator, VkSurfaceKHR *surface) {
    VkResult result = next_create_metal_surface(instance, info, allocator, surface);
    if (result == VK_SUCCESS) {
        static unsigned next_slot;
        pthread_mutex_lock(&upscaled_lock);
        surfaces[next_slot % 16].surface = *surface;
        surfaces[next_slot % 16].layer = (void *)info->pLayer;
        next_slot++;
        pthread_mutex_unlock(&upscaled_lock);
    }
    return result;
}

static void *layer_of(VkSurfaceKHR surface) {
    for (int i = 0; i < 16; i++)
        if (surfaces[i].surface == surface) return surfaces[i].layer;
    return NULL;
}

static void *metal_texture(VkImage image) {
    VkExportMetalTextureInfoEXT texture = {VK_STRUCTURE_TYPE_EXPORT_METAL_TEXTURE_INFO_EXT};
    texture.image = image;
    texture.plane = VK_IMAGE_ASPECT_PLANE_0_BIT;
    VkExportMetalObjectsInfoEXT request = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT, &texture};
    metal.export_objects(metal.device, &request);
    return (void *)texture.mtlTexture;
}

static void free_upscaled(VkDevice device, struct upscaled *u) {
    for (uint32_t i = 0; i < u->count; i++) {
        if (u->images[i]) metal.destroy_image(device, u->images[i], NULL);
        if (u->memory[i]) metal.free_memory(device, u->memory[i], NULL);
    }
    nf_scaler_release(u->scaler);
    free(u);
}

/// The game's own images: its size and format, usable by MetalFX as well.
static int create_game_images(VkDevice device, const VkSwapchainCreateInfoKHR *info, struct upscaled *u) {
    for (uint32_t i = 0; i < u->count; i++) {
        VkImageCreateInfo image = {VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
        image.imageType = VK_IMAGE_TYPE_2D;
        image.format = info->imageFormat;
        image.extent = (VkExtent3D){u->size.width, u->size.height, 1};
        image.mipLevels = 1;
        image.arrayLayers = info->imageArrayLayers ? info->imageArrayLayers : 1;
        image.samples = VK_SAMPLE_COUNT_1_BIT;
        image.tiling = VK_IMAGE_TILING_OPTIMAL;
        image.usage = info->imageUsage | VK_IMAGE_USAGE_SAMPLED_BIT;
        if (info->flags & VK_SWAPCHAIN_CREATE_MUTABLE_FORMAT_BIT_KHR) image.flags |= VK_IMAGE_CREATE_MUTABLE_FORMAT_BIT;
        image.sharingMode = info->imageSharingMode;
        image.queueFamilyIndexCount = info->queueFamilyIndexCount;
        image.pQueueFamilyIndices = info->pQueueFamilyIndices;
        image.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        if (metal.create_image(device, &image, NULL, &u->images[i]) != VK_SUCCESS) return 0;

        VkMemoryRequirements needs;
        metal.image_requirements(device, u->images[i], &needs);
        uint32_t type = UINT32_MAX;
        for (uint32_t t = 0; t < metal.memory.memoryTypeCount && type == UINT32_MAX; t++)
            if ((needs.memoryTypeBits & (1u << t)) &&
                (metal.memory.memoryTypes[t].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT))
                type = t;
        if (type == UINT32_MAX) return 0;
        VkMemoryAllocateInfo allocation = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, NULL, needs.size, type};
        if (metal.allocate(device, &allocation, NULL, &u->memory[i]) != VK_SUCCESS) return 0;
        if (metal.bind(device, u->images[i], u->memory[i], 0) != VK_SUCCESS) return 0;
        if (!(u->textures[i] = metal_texture(u->images[i]))) return 0;
    }
    return 1;
}

static VKAPI_ATTR VkResult VKAPI_CALL CreateSwapchainKHR(VkDevice device, const VkSwapchainCreateInfoKHR *info,
                                                         const VkAllocationCallbacks *allocator, VkSwapchainKHR *swapchain) {
    VkExtent2D size = info->imageExtent, target = size;
    int scale = allow_upscale && !upscale_failed && metal.mtl_device && device == metal.device &&
                info->imageColorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR ? nf_display_scale() : 1;
    if (scale > 1) {
        // The window's Retina pixels; its size in points comes from the surface's layer when known.
        uint32_t width = size.width, height = size.height;
        nf_layer_size(layer_of(info->surface), &width, &height);
        target = (VkExtent2D){width * scale, height * scale};
    }
    struct upscaled *u = NULL;
    if (target.width > size.width && target.height > size.height) {
        u = calloc(1, sizeof *u);
        if (u) u->scaler = nf_scaler_create(metal.mtl_device, info->imageFormat, size.width, size.height,
                                            target.width, target.height);
        if (u && !u->scaler) {
            free(u);
            u = NULL;
        }
    }
    fprintf(stderr, "[nightforge-vulkan] swapchain %ux%u format %d colour space %d%s", size.width, size.height,
            info->imageFormat, info->imageColorSpace, allow_hdr ? " (HDR allowed)" : "");
    if (!u) {
        fprintf(stderr, "\n");
        return next_create_swapchain(device, info, allocator, swapchain);
    }
    fprintf(stderr, ", MetalFX to %ux%u\n", target.width, target.height);

    // The real swapchain: Retina size, writable by MetalFX, and marked as deliberately scaled so
    // MoltenVK doesn't call it suboptimal for differing from the layer's size in points.
    VkSwapchainPresentScalingCreateInfoEXT scaling = {VK_STRUCTURE_TYPE_SWAPCHAIN_PRESENT_SCALING_CREATE_INFO_EXT};
    scaling.pNext = info->pNext;
    scaling.scalingBehavior = VK_PRESENT_SCALING_STRETCH_BIT_EXT;
    VkSwapchainCreateInfoKHR real = *info;
    real.pNext = &scaling;
    real.imageExtent = target;
    real.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    VkResult result = next_create_swapchain(device, &real, allocator, swapchain);
    if (result != VK_SUCCESS) {
        nf_scaler_release(u->scaler);
        free(u);
        return result;
    }
    u->handle = *swapchain;
    u->size = size;
    u->target = target;
    u->count = MAX_IMAGES;
    if (next_get_swapchain_images(device, *swapchain, &u->count, u->real) < 0 || !create_game_images(device, info, u)) {
        // Not enough for the game's own images: start over with the plain swapchain.
        free_upscaled(device, u);
        next_destroy_swapchain(device, *swapchain, allocator);
        upscale_failed = 1;
        return next_create_swapchain(device, info, allocator, swapchain);
    }
    pthread_mutex_lock(&upscaled_lock);
    u->next = upscaled_list;
    upscaled_list = u;
    pthread_mutex_unlock(&upscaled_lock);
    return VK_SUCCESS;
}

static VKAPI_ATTR void VKAPI_CALL DestroySwapchainKHR(VkDevice device, VkSwapchainKHR swapchain,
                                                      const VkAllocationCallbacks *allocator) {
    pthread_mutex_lock(&upscaled_lock);
    struct upscaled **link = &upscaled_list;
    while (*link && (*link)->handle != swapchain) link = &(*link)->next;
    struct upscaled *u = *link;
    if (u) *link = u->next;
    pthread_mutex_unlock(&upscaled_lock);
    if (u) {
        metal.wait_idle(device);  // the game's images may still be read by MetalFX
        free_upscaled(device, u);
    }
    next_destroy_swapchain(device, swapchain, allocator);
}

/// The game gets its own images in place of the real ones; the indices stay the same.
static VKAPI_ATTR VkResult VKAPI_CALL GetSwapchainImagesKHR(VkDevice device, VkSwapchainKHR swapchain,
                                                            uint32_t *count, VkImage *images) {
    pthread_mutex_lock(&upscaled_lock);
    struct upscaled *u = find_upscaled(swapchain);
    pthread_mutex_unlock(&upscaled_lock);
    if (!u) return next_get_swapchain_images(device, swapchain, count, images);
    if (!images) {
        *count = u->count;
        return VK_SUCCESS;
    }
    uint32_t n = *count < u->count ? *count : u->count;
    memcpy(images, u->images, n * sizeof *images);
    *count = n;
    return n < u->count ? VK_INCOMPLETE : VK_SUCCESS;
}

/// Before MoltenVK presents: the game's frames scaled into the real swapchain images. The present's
/// semaphores are waited for by an empty submission first; everything after it runs in order on
/// the queue's Metal command queue. Returns the present to hand on (without those semaphores), or
/// NULL when there's nothing to upscale. `*recreate` says an upscale failed.
static const VkPresentInfoKHR *upscale(VkQueue queue, const VkPresentInfoKHR *info, VkPresentInfoKHR *copy, int *recreate) {
    struct upscaled *found[16] = {0};
    int any = 0;
    pthread_mutex_lock(&upscaled_lock);
    for (uint32_t i = 0; i < info->swapchainCount && i < 16; i++)
        if ((found[i] = find_upscaled(info->pSwapchains[i]))) any = 1;
    pthread_mutex_unlock(&upscaled_lock);
    if (!any) return NULL;

    if (info->waitSemaphoreCount) {
        VkPipelineStageFlags stages[32];
        uint32_t waits = info->waitSemaphoreCount < 32 ? info->waitSemaphoreCount : 32;
        for (uint32_t i = 0; i < waits; i++) stages[i] = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
        VkSubmitInfo submit = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
        submit.waitSemaphoreCount = waits;
        submit.pWaitSemaphores = info->pWaitSemaphores;
        submit.pWaitDstStageMask = stages;
        if (metal.queue_submit(queue, 1, &submit, VK_NULL_HANDLE) != VK_SUCCESS) return NULL;
    }
    VkExportMetalCommandQueueInfoEXT commands = {VK_STRUCTURE_TYPE_EXPORT_METAL_COMMAND_QUEUE_INFO_EXT};
    commands.queue = queue;
    VkExportMetalObjectsInfoEXT request = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT, &commands};
    metal.export_objects(metal.device, &request);

    for (uint32_t i = 0; i < info->swapchainCount && i < 16; i++) {
        struct upscaled *u = found[i];
        if (!u || u->broken) continue;
        uint32_t index = info->pImageIndices[i];
        if (index >= u->count ||
            !nf_upscale((void *)commands.mtlCommandQueue, u->scaler, u->textures[index], metal_texture(u->real[index]))) {
            u->broken = 1;
            upscale_failed = 1;
            *recreate = 1;
            fprintf(stderr, "[nightforge-vulkan] MetalFX upscaling failed, back to the plain swapchain\n");
        }
    }
    *copy = *info;
    copy->waitSemaphoreCount = 0;
    copy->pWaitSemaphores = NULL;
    return copy;
}

// MARK: - Frame rate

static double now_seconds(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec / 1e9;
}

/// The game's program ("Game.exe"), named in each frame-rate line: wine.log is shared by all games.
static const char *program_name(void) {
    char **argv = *_NSGetArgv();
    if (!argv || !argv[0]) return "?";
    const char *name = argv[0];
    for (const char *c = argv[0]; *c; c++) if (*c == '\\' || *c == '/') name = c + 1;
    return name;
}

static VKAPI_ATTR VkResult VKAPI_CALL QueuePresentKHR(VkQueue queue, const VkPresentInfoKHR *info) {
    static double started, period_start, last;
    static unsigned frames;
    static double slowest;
    double time = now_seconds();
    if (started == 0) started = period_start = last = time;
    if (time - last > slowest) slowest = time - last;
    last = time;
    frames++;
    double period = time - started < 120 ? 10 : 60;
    if (time - period_start >= period) {
        double seconds = time - period_start;
        fprintf(stderr, "[nightforge-vulkan] %s: %.1f FPS over %.0f s, frames %.1f ms on average, slowest %.0f ms\n",
                program_name(), frames / seconds, seconds, seconds * 1000 / frames, slowest * 1000);
        period_start = time;
        frames = 0;
        slowest = 0;
    }
    VkPresentInfoKHR copy;
    int recreate = 0;
    const VkPresentInfoKHR *upscaled = upscale(queue, info, &copy, &recreate);
    VkResult result = next_queue_present(queue, upscaled ? upscaled : info);
    // The game recreates its swapchain on this, and gets the plain one then.
    return recreate && result >= 0 ? VK_ERROR_OUT_OF_DATE_KHR : result;
}

// MARK: - Instance and device

static VKAPI_ATTR VkResult VKAPI_CALL CreateInstance(const VkInstanceCreateInfo *info,
                                                     const VkAllocationCallbacks *allocator, VkInstance *instance) {
    VkLayerInstanceCreateInfo *link = (VkLayerInstanceCreateInfo *)info->pNext;
    while (link && !(link->sType == VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO && link->function == VK_LAYER_LINK_INFO))
        link = (VkLayerInstanceCreateInfo *)link->pNext;
    if (!link) return VK_ERROR_INITIALIZATION_FAILED;
    PFN_vkGetInstanceProcAddr next = link->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    link->u.pLayerInfo = link->u.pLayerInfo->pNext;

    PFN_vkCreateInstance create = (PFN_vkCreateInstance)next(VK_NULL_HANDLE, "vkCreateInstance");
    VkResult result = create(info, allocator, instance);
    if (result != VK_SUCCESS) return result;
    // The next link is the loader itself, the same for every instance.
    next_instance_proc = next;
    first_instance = first_instance ? first_instance : *instance;
    next_features = (PFN_vkGetPhysicalDeviceFeatures)next(*instance, "vkGetPhysicalDeviceFeatures");
    next_properties = (PFN_vkGetPhysicalDeviceProperties)next(*instance, "vkGetPhysicalDeviceProperties");
    return VK_SUCCESS;
}

/// Turns off what the game asks for and the device lacks; false when there was nothing to do.
static int drop_unsupported(VkPhysicalDeviceFeatures *requested, const VkPhysicalDeviceFeatures *supported) {
    VkBool32 *wanted = (VkBool32 *)requested;
    const VkBool32 *available = (const VkBool32 *)supported;
    int dropped = 0;
    for (size_t i = 0; i < sizeof(VkPhysicalDeviceFeatures) / sizeof(VkBool32); i++)
        if (wanted[i] && !available[i]) {
            wanted[i] = VK_FALSE;
            dropped = 1;
        }
    return dropped;
}

/// What upscaling needs from the first device that has VK_EXT_metal_objects.
static void set_up_metal(VkPhysicalDevice physical, VkDevice device, PFN_vkGetInstanceProcAddr next) {
    PFN_vkGetPhysicalDeviceMemoryProperties memory =
        (PFN_vkGetPhysicalDeviceMemoryProperties)next(first_instance, "vkGetPhysicalDeviceMemoryProperties");
#define DEVICE_PROC(field, type, name) metal.field = (type)next_device_proc(device, name)
    DEVICE_PROC(export_objects, PFN_vkExportMetalObjectsEXT, "vkExportMetalObjectsEXT");
    DEVICE_PROC(queue_submit, PFN_vkQueueSubmit, "vkQueueSubmit");
    DEVICE_PROC(create_image, PFN_vkCreateImage, "vkCreateImage");
    DEVICE_PROC(destroy_image, PFN_vkDestroyImage, "vkDestroyImage");
    DEVICE_PROC(image_requirements, PFN_vkGetImageMemoryRequirements, "vkGetImageMemoryRequirements");
    DEVICE_PROC(allocate, PFN_vkAllocateMemory, "vkAllocateMemory");
    DEVICE_PROC(free_memory, PFN_vkFreeMemory, "vkFreeMemory");
    DEVICE_PROC(bind, PFN_vkBindImageMemory, "vkBindImageMemory");
    DEVICE_PROC(wait_idle, PFN_vkDeviceWaitIdle, "vkDeviceWaitIdle");
#undef DEVICE_PROC
    if (!next_destroy_swapchain) next_destroy_swapchain = (PFN_vkDestroySwapchainKHR)next_device_proc(device, "vkDestroySwapchainKHR");
    if (!next_get_swapchain_images)
        next_get_swapchain_images = (PFN_vkGetSwapchainImagesKHR)next_device_proc(device, "vkGetSwapchainImagesKHR");
    if (!memory || !metal.export_objects || !metal.queue_submit || !metal.create_image || !metal.destroy_image ||
        !metal.image_requirements || !metal.allocate || !metal.free_memory || !metal.bind || !metal.wait_idle ||
        !next_destroy_swapchain || !next_get_swapchain_images)
        return;
    memory(physical, &metal.memory);
    VkExportMetalDeviceInfoEXT mtl = {VK_STRUCTURE_TYPE_EXPORT_METAL_DEVICE_INFO_EXT};
    VkExportMetalObjectsInfoEXT request = {VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT, &mtl};
    metal.export_objects(device, &request);
    metal.mtl_device = (void *)mtl.mtlDevice;
    metal.device = device;
}

static VKAPI_ATTR VkResult VKAPI_CALL CreateDevice(VkPhysicalDevice physicalDevice, const VkDeviceCreateInfo *info,
                                                   const VkAllocationCallbacks *allocator, VkDevice *device) {
    VkLayerDeviceCreateInfo *link = (VkLayerDeviceCreateInfo *)info->pNext;
    while (link && !(link->sType == VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO && link->function == VK_LAYER_LINK_INFO))
        link = (VkLayerDeviceCreateInfo *)link->pNext;
    if (!link) return VK_ERROR_INITIALIZATION_FAILED;
    PFN_vkGetInstanceProcAddr next = link->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    next_device_proc = link->u.pLayerInfo->pfnNextGetDeviceProcAddr;
    link->u.pLayerInfo = link->u.pLayerInfo->pNext;

    VkPhysicalDeviceFeatures supported;
    next_features(physicalDevice, &supported);
    VkDeviceCreateInfo copy = *info;
    VkPhysicalDeviceFeatures enabled;
    if (info->pEnabledFeatures) {
        enabled = *info->pEnabledFeatures;
        drop_unsupported(&enabled, &supported);
        copy.pEnabledFeatures = &enabled;
    }
    // Features can also come in the pNext chain, which belongs to the game: changed for the call only.
    VkPhysicalDeviceFeatures2 *chained = NULL;
    for (VkBaseOutStructure *s = (VkBaseOutStructure *)info->pNext; s; s = s->pNext)
        if (s->sType == VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2) chained = (VkPhysicalDeviceFeatures2 *)s;
    VkPhysicalDeviceFeatures original, trimmed;
    if (chained) {
        original = trimmed = chained->features;
        if (drop_unsupported(&trimmed, &supported)) chained->features = trimmed;
        else chained = NULL;
    }

    // Upscaling reaches MoltenVK's Metal objects through VK_EXT_metal_objects.
    pthread_once(&config_once, load_config);
    const char *extensions[64];
    int metal_objects = 0;
    if (allow_upscale && info->enabledExtensionCount < 63) {
        PFN_vkEnumerateDeviceExtensionProperties enumerate =
            (PFN_vkEnumerateDeviceExtensionProperties)next(first_instance, "vkEnumerateDeviceExtensionProperties");
        uint32_t count = 0;
        VkExtensionProperties *available = NULL;
        if (enumerate && enumerate(physicalDevice, NULL, &count, NULL) == VK_SUCCESS && count &&
            (available = calloc(count, sizeof *available)) && enumerate(physicalDevice, NULL, &count, available) >= 0)
            for (uint32_t i = 0; i < count; i++)
                if (!strcmp(available[i].extensionName, VK_EXT_METAL_OBJECTS_EXTENSION_NAME)) metal_objects = 1;
        free(available);
        if (metal_objects) {
            int listed = 0;
            for (uint32_t i = 0; i < info->enabledExtensionCount; i++) {
                extensions[i] = info->ppEnabledExtensionNames[i];
                if (!strcmp(extensions[i], VK_EXT_METAL_OBJECTS_EXTENSION_NAME)) listed = 1;
            }
            if (!listed) {
                extensions[info->enabledExtensionCount] = VK_EXT_METAL_OBJECTS_EXTENSION_NAME;
                copy.enabledExtensionCount = info->enabledExtensionCount + 1;
                copy.ppEnabledExtensionNames = extensions;
            }
        }
    }

    PFN_vkCreateDevice create = (PFN_vkCreateDevice)next(VK_NULL_HANDLE, "vkCreateDevice");
    VkResult result = create(physicalDevice, &copy, allocator, device);
    if (chained) chained->features = original;
    if (result == VK_SUCCESS && metal_objects && !metal.device) set_up_metal(physicalDevice, *device, next);
    return result;
}

// MARK: - Entry points

static VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL GetDeviceProcAddr(VkDevice device, const char *name) {
    if (!strcmp(name, "vkGetDeviceProcAddr")) return (PFN_vkVoidFunction)GetDeviceProcAddr;
    PFN_vkVoidFunction theirs = next_device_proc(device, name);
    if (theirs && !strcmp(name, "vkCreateSwapchainKHR")) {
        if (!next_create_swapchain) next_create_swapchain = (PFN_vkCreateSwapchainKHR)theirs;
        return (PFN_vkVoidFunction)CreateSwapchainKHR;
    }
    if (theirs && !strcmp(name, "vkDestroySwapchainKHR")) {
        if (!next_destroy_swapchain) next_destroy_swapchain = (PFN_vkDestroySwapchainKHR)theirs;
        return (PFN_vkVoidFunction)DestroySwapchainKHR;
    }
    if (theirs && !strcmp(name, "vkGetSwapchainImagesKHR")) {
        if (!next_get_swapchain_images) next_get_swapchain_images = (PFN_vkGetSwapchainImagesKHR)theirs;
        return (PFN_vkVoidFunction)GetSwapchainImagesKHR;
    }
    if (theirs && !strcmp(name, "vkQueuePresentKHR")) {
        if (!next_queue_present) next_queue_present = (PFN_vkQueuePresentKHR)theirs;
        return (PFN_vkVoidFunction)QueuePresentKHR;
    }
    return theirs;
}

static VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL GetInstanceProcAddr(VkInstance instance, const char *name) {
    static const struct { const char *name; PFN_vkVoidFunction function; } own[] = {
        {"vkGetInstanceProcAddr", (PFN_vkVoidFunction)GetInstanceProcAddr},
        {"vkGetDeviceProcAddr", (PFN_vkVoidFunction)GetDeviceProcAddr},
        {"vkCreateInstance", (PFN_vkVoidFunction)CreateInstance},
        {"vkCreateDevice", (PFN_vkVoidFunction)CreateDevice},
        {"vkGetPhysicalDeviceFeatures", (PFN_vkVoidFunction)GetPhysicalDeviceFeatures},
        {"vkGetPhysicalDeviceProperties", (PFN_vkVoidFunction)GetPhysicalDeviceProperties},
    };
    for (size_t i = 0; i < sizeof own / sizeof *own; i++)
        if (!strcmp(name, own[i].name)) return own[i].function;
    PFN_vkVoidFunction theirs = next_instance_proc ? next_instance_proc(instance, name) : NULL;
    // The "2" queries exist only from Vulkan 1.1 or with an extension: wrapped where the loader has them.
    if (theirs && (!strcmp(name, "vkGetPhysicalDeviceFeatures2") || !strcmp(name, "vkGetPhysicalDeviceFeatures2KHR"))) {
        if (!next_features2) next_features2 = (PFN_vkGetPhysicalDeviceFeatures2)theirs;
        return (PFN_vkVoidFunction)GetPhysicalDeviceFeatures2;
    }
    if (theirs && (!strcmp(name, "vkGetPhysicalDeviceProperties2") || !strcmp(name, "vkGetPhysicalDeviceProperties2KHR"))) {
        if (!next_properties2) next_properties2 = (PFN_vkGetPhysicalDeviceProperties2)theirs;
        return (PFN_vkVoidFunction)GetPhysicalDeviceProperties2;
    }
    if (theirs && !strcmp(name, "vkCreateMetalSurfaceEXT")) {
        if (!next_create_metal_surface) next_create_metal_surface = (PFN_vkCreateMetalSurfaceEXT)theirs;
        return (PFN_vkVoidFunction)CreateMetalSurfaceEXT;
    }
    if (theirs && !strcmp(name, "vkGetPhysicalDeviceSurfaceFormatsKHR")) {
        if (!next_surface_formats) next_surface_formats = (PFN_vkGetPhysicalDeviceSurfaceFormatsKHR)theirs;
        return (PFN_vkVoidFunction)GetPhysicalDeviceSurfaceFormatsKHR;
    }
    if (theirs && !strcmp(name, "vkGetPhysicalDeviceSurfaceFormats2KHR")) {
        if (!next_surface_formats2) next_surface_formats2 = (PFN_vkGetPhysicalDeviceSurfaceFormats2KHR)theirs;
        return (PFN_vkVoidFunction)GetPhysicalDeviceSurfaceFormats2KHR;
    }
    return theirs;
}

EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkNegotiateLoaderLayerInterfaceVersion(VkNegotiateLayerInterface *interface) {
    if (interface->loaderLayerInterfaceVersion > 2) interface->loaderLayerInterfaceVersion = 2;
    interface->pfnGetInstanceProcAddr = GetInstanceProcAddr;
    interface->pfnGetDeviceProcAddr = GetDeviceProcAddr;
    interface->pfnGetPhysicalDeviceProcAddr = NULL;
    return VK_SUCCESS;
}
