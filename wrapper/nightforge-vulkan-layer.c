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
//     on a Mac's XDR display games otherwise pick HDR, which under Wine mostly looks washed out.
// Per-game settings come from nightforge-vulkan.conf next to the game's program (written by
// Nightforge before each start, like dxmt.conf):
//         maxPerStageDescriptorSamplers = 64
//         hdr = on
// Each swapchain's size, format and colour space goes to stderr, i.e. Nightforge's wine.log, and
// so does the frame rate: every 10 s for the first two minutes, then every minute.
//
// Inside the "Nightforge Game" bundle the Vulkan loader finds it as an implicit layer in
// Contents/Resources/vulkan/implicit_layer.d (see Engine.installVulkanLayer).
//
// Build (x86_64, like Wine): clang -arch x86_64 -dynamiclib -fvisibility=hidden
//     -I vulkan-headers -o nightforge-vulkan-layer.dylib nightforge-vulkan-layer.c

#include <crt_externs.h>
#include <limits.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <vulkan/vk_layer.h>

#define EXPORT __attribute__((visibility("default")))

static PFN_vkGetInstanceProcAddr next_instance_proc;
static PFN_vkGetDeviceProcAddr next_device_proc;
static PFN_vkGetPhysicalDeviceFeatures next_features;
static PFN_vkGetPhysicalDeviceFeatures2 next_features2;
static PFN_vkGetPhysicalDeviceProperties next_properties;
static PFN_vkGetPhysicalDeviceProperties2 next_properties2;
static PFN_vkGetPhysicalDeviceSurfaceFormatsKHR next_surface_formats;
static PFN_vkGetPhysicalDeviceSurfaceFormats2KHR next_surface_formats2;
static PFN_vkCreateSwapchainKHR next_create_swapchain;
static PFN_vkQueuePresentKHR next_queue_present;

// MARK: - Configuration

static uint32_t min_samplers = 32;
static int allow_hdr = 0;

static int read_config(const char *path) {
    FILE *file = fopen(path, "r");
    if (!file) return 0;
    char line[256];
    while (fgets(line, sizeof line, file)) {
        unsigned value;
        char word[16];
        if (sscanf(line, " maxPerStageDescriptorSamplers = %u", &value) == 1) min_samplers = value;
        if (sscanf(line, " hdr = %15s", word) == 1) allow_hdr = !strcmp(word, "on");
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

static VKAPI_ATTR VkResult VKAPI_CALL CreateSwapchainKHR(VkDevice device, const VkSwapchainCreateInfoKHR *info,
                                                         const VkAllocationCallbacks *allocator, VkSwapchainKHR *swapchain) {
    fprintf(stderr, "[nightforge-vulkan] swapchain %ux%u format %d colour space %d%s\n", info->imageExtent.width,
            info->imageExtent.height, info->imageFormat, info->imageColorSpace, allow_hdr ? " (HDR allowed)" : "");
    return next_create_swapchain(device, info, allocator, swapchain);
}

// MARK: - Frame rate

static double now_seconds(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return time.tv_sec + time.tv_nsec / 1e9;
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
        fprintf(stderr, "[nightforge-vulkan] %.1f FPS, frames %.1f ms on average, slowest %.0f ms\n",
                frames / seconds, seconds * 1000 / frames, slowest * 1000);
        period_start = time;
        frames = 0;
        slowest = 0;
    }
    return next_queue_present(queue, info);
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

    PFN_vkCreateDevice create = (PFN_vkCreateDevice)next(VK_NULL_HANDLE, "vkCreateDevice");
    VkResult result = create(physicalDevice, &copy, allocator, device);
    if (chained) chained->features = original;
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
