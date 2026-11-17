#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================================
#  experimento-ollama-vulkan-adreno840.sh  (v2 — Anti-Signal-9 + Dual Vulkan/OpenCL)
#  Compilación Experimental Aislada y Verificación de Hardware GPU Real
#  Objetivo : Xiaomi POCO F8 Ultra (512 GB | Android 16 SDK 36 | SoC 'canoe')
#  GPU      : Qualcomm Adreno 840 (/dev/kgsl-3d0)
#  Backends : 1) Vulkan Nativo (/system/lib64/libvulkan.so -> vulkan.adreno.so)
#             2) OpenCL Nativo (Android 16 'sphal' -> /vendor/lib64/libOpenCL.so)
#             3) Sonda OpenGL ES 3.2 (diagnóstico técnico EGL/GLESv3)
#  Ollama   : v0.40.16 + llama.cpp b12177 adaptado para Adreno 840 (sin root)
# ==============================================================================
#  CORRECCIONES CLAVE v2:
#    • Elimina el cierre por 'signal 9' (SIGKILL) del PhantomProcessKiller de
#      Android: reduce concurrencia a 2 glslc por generador + Ninja -j2.
#      Mitigación de presión de memoria/procesos; no garantiza evitar SIGKILL.
#    • Elimina los 'CMake Warning: Expected depfile does not exist' en shaders
#      _cm1/_cm2 generando siempre el archivo .d válido para Ninja.
#    • Implementa además el backend Qualcomm Adreno OpenCL (sphal sin root) y
#      compara en vivo CPU Original vs GPU Vulkan vs GPU OpenCL (ctx=73728).
#    • Preserva 100% intactos $PREFIX/bin/ollama, ~/.ollama, Q4_K_M y ctx=73728.
#
#  EJECUCIÓN EN TERMUX:
#    bash ~/storage/downloads/experimento-ollama-vulkan-adreno840.sh
# ==============================================================================

set -euo pipefail

SOLO_PRUEBAS=0
RECOMPILAR=0
SKIP_AUDIT=0

for arg in "$@"; do
  case "$arg" in
    --skip-audit) SKIP_AUDIT=1 ;;
    --solo-pruebas) SOLO_PRUEBAS=1 ;;
    --recompilar)   RECOMPILAR=1 ;;
    -h|--help)
      printf '%s\n' 'Uso: build-adreno.sh [--skip-audit] [--solo-pruebas] [--recompilar]'
      sed -n '2,25p' "$0" | sed 's/^# \{0,2\}//'
      exit 0
      ;;
    *)
      echo "[✗] Opción desconocida: $arg (usa --help)" >&2
      exit 1
      ;;
  esac
done

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
EXP_DIR="$HOME/ollama-vulkan-exp"
SRC_DIR="$EXP_DIR/src"
PATCH_DIR="$EXP_DIR/patches"
LOG_DIR="$EXP_DIR/logs"
CL_CACHE_DIR="$EXP_DIR/cl-cache"
MODEL_TARGET="${MODEL_TARGET:-qwen35-4b-uncensored}"
CTX_TARGET="${CTX_TARGET:-73728}"
EXP_PORT=11435

C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'

info() { printf '%s\n' "${C_CYAN}[*]${C_RESET} $*"; }
ok()   { printf '%s\n' "${C_GREEN}[✓]${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YELLOW}[!]${C_RESET} $*" >&2; }
die()  { printf '%s\n' "${C_RED}[✗]${C_RESET} $*" >&2; exit 1; }

printf '\n%s\n' "${C_BOLD}╔══════════════════════════════════════════════════════════════════════╗${C_RESET}"
printf '%s\n'   "${C_BOLD}║  Ollama 0.40.16 Experimental — Adreno 840 (Vulkan + OpenCL SPHAL)    ║${C_RESET}"
printf '%s\n\n' "${C_BOLD}╚══════════════════════════════════════════════════════════════════════╝${C_RESET}"

# --------------------------- 0. Verificaciones previas del entorno ------------
[ -d "/data/data/com.termux" ] || die "Ejecuta este script dentro de Termux en tu POCO F8 Ultra."
[ "$(uname -m)" = "aarch64" ]  || die "Se requiere arquitectura aarch64."
[ -f "/system/lib64/libvulkan.so" ] || die "No existe /system/lib64/libvulkan.so."
[ -e "/dev/kgsl-3d0" ] || die "No existe /dev/kgsl-3d0."

command -v termux-wake-lock >/dev/null 2>&1 && { termux-wake-lock || true; }

mkdir -p "$EXP_DIR/bin" "$EXP_DIR/lib/ollama/vulkan" "$EXP_DIR/lib/ollama/opencl" \
         "$SRC_DIR" "$PATCH_DIR" "$LOG_DIR" "$CL_CACHE_DIR"

# Las sondas de Fase 1 también necesitan compilador, incluso con --solo-pruebas.
export PATH="$PREFIX/bin:$PATH"
if ! command -v clang >/dev/null 2>&1; then
  command -v pkg >/dev/null 2>&1 || die "No se encuentra pkg en Termux. Revisa PREFIX y PATH."
  info "Instalando clang antes de compilar las sondas de hardware..."
  pkg update -y || die "Falló pkg update. Revisa tu conexión y los repositorios de Termux."
  pkg install -y clang || die "No se pudo instalar clang. Ejecuta: pkg install clang"
fi
command -v clang >/dev/null 2>&1 || die "clang sigue sin estar disponible tras instalarlo."

# --------------------------- 1. FASE 1: Sondas C Nativas (Vulkan/OpenCL/GLES) -
info "FASE 1/5 — Probando acceso directo sin root a Adreno 840 en Vulkan, OpenCL y OpenGL ES..."

# 1A. Sonda Vulkan Nativa (/system/lib64/libvulkan.so -> vulkan.adreno.so)
cat <<'PROBE_VK_EOF' > "$SRC_DIR/vk_adreno_probe.c"
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>

typedef uint32_t VkFlags;
typedef uint32_t VkBool32;
typedef uint64_t VkDeviceSize;
typedef int32_t  VkResult;
typedef void*    VkInstance;
typedef void*    VkPhysicalDevice;
typedef void*    VkDevice;
typedef void (*PFN_vkVoidFunction)(void);

#define VK_SUCCESS 0
#define VK_STRUCTURE_TYPE_APPLICATION_INFO 0
#define VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO 1
#define VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO 2
#define VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO 3
#define VK_QUEUE_COMPUTE_BIT 0x00000002U
#define VK_MAKE_API_VERSION(v, ma, mi, pa) ((((uint32_t)(v)) << 29U) | (((uint32_t)(ma)) << 22U) | (((uint32_t)(mi)) << 12U) | ((uint32_t)(pa)))
#define VK_API_VER_MAJOR(v) (((uint32_t)(v) >> 22U) & 0x7FU)
#define VK_API_VER_MINOR(v) (((uint32_t)(v) >> 12U) & 0x3FFU)
#define VK_API_VER_PATCH(v) ((uint32_t)(v) & 0xFFFU)

typedef enum VkPhysicalDeviceType {
    VK_PHYSICAL_DEVICE_TYPE_OTHER = 0,
    VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU = 1,
    VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU = 2,
    VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU = 3,
    VK_PHYSICAL_DEVICE_TYPE_CPU = 4
} VkPhysicalDeviceType;

typedef struct VkApplicationInfo {
    int32_t sType; const void *pNext; const char *pApplicationName; uint32_t applicationVersion;
    const char *pEngineName; uint32_t engineVersion; uint32_t apiVersion;
} VkApplicationInfo;

typedef struct VkInstanceCreateInfo {
    int32_t sType; const void *pNext; VkFlags flags; const VkApplicationInfo *pApplicationInfo;
    uint32_t enabledLayerCount; const char * const *ppEnabledLayerNames;
    uint32_t enabledExtensionCount; const char * const *ppEnabledExtensionNames;
} VkInstanceCreateInfo;

typedef struct VkExtent3D { uint32_t width, height, depth; } VkExtent3D;

typedef struct VkPhysicalDeviceProperties {
    uint32_t apiVersion;
    uint32_t driverVersion;
    uint32_t vendorID;
    uint32_t deviceID;
    VkPhysicalDeviceType deviceType;
    char deviceName[256];
    uint8_t pipelineCacheUUID[16];
    uint8_t _tail[600];
} VkPhysicalDeviceProperties;

typedef struct VkQueueFamilyProperties {
    VkFlags queueFlags;
    uint32_t queueCount;
    uint32_t timestampValidBits;
    VkExtent3D minImageTransferGranularity;
} VkQueueFamilyProperties;

typedef struct VkDeviceQueueCreateInfo {
    int32_t sType; const void *pNext; VkFlags flags;
    uint32_t queueFamilyIndex; uint32_t queueCount; const float *pQueuePriorities;
} VkDeviceQueueCreateInfo;

typedef struct VkDeviceCreateInfo {
    int32_t sType; const void *pNext; VkFlags flags;
    uint32_t queueCreateInfoCount; const VkDeviceQueueCreateInfo *pQueueCreateInfos;
    uint32_t enabledLayerCount; const char * const *ppEnabledLayerNames;
    uint32_t enabledExtensionCount; const char * const *ppEnabledExtensionNames;
    const void *pEnabledFeatures;
} VkDeviceCreateInfo;

typedef PFN_vkVoidFunction (*PFN_vkGetInstanceProcAddr)(VkInstance, const char*);
typedef PFN_vkVoidFunction (*PFN_vkGetDeviceProcAddr)(VkDevice, const char*);
typedef VkResult (*PFN_vkCreateInstance)(const VkInstanceCreateInfo*, const void*, VkInstance*);
typedef void     (*PFN_vkDestroyInstance)(VkInstance, const void*);
typedef VkResult (*PFN_vkEnumeratePhysicalDevices)(VkInstance, uint32_t*, VkPhysicalDevice*);
typedef void     (*PFN_vkGetPhysicalDeviceProperties)(VkPhysicalDevice, VkPhysicalDeviceProperties*);
typedef void     (*PFN_vkGetPhysicalDeviceQueueFamilyProperties)(VkPhysicalDevice, uint32_t*, VkQueueFamilyProperties*);
typedef VkResult (*PFN_vkCreateDevice)(VkPhysicalDevice, const VkDeviceCreateInfo*, const void*, VkDevice*);
typedef void     (*PFN_vkDestroyDevice)(VkDevice, const void*);

static const char *dev_type_str(VkPhysicalDeviceType t) {
    switch (t) {
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU: return "INTEGRATED_GPU (Hardware Real)";
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:   return "DISCRETE_GPU (Hardware Real)";
        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:    return "VIRTUAL_GPU";
        case VK_PHYSICAL_DEVICE_TYPE_CPU:            return "CPU (Software/llvmpipe)";
        default:                                     return "OTHER";
    }
}

int main(int argc, char **argv) {
    const char *loader_path = (argc > 1) ? argv[1] : "/system/lib64/libvulkan.so";
    unsetenv("VK_ICD_FILENAMES");
    unsetenv("VK_DRIVER_FILES");

    void *lib = dlopen(loader_path, RTLD_NOW | RTLD_LOCAL);
    if (!lib) {
        fprintf(stderr, "[ERROR] dlopen(%s) fallo: %s\n", loader_path, dlerror());
        return 1;
    }

    PFN_vkGetInstanceProcAddr gipa = (PFN_vkGetInstanceProcAddr)dlsym(lib, "vkGetInstanceProcAddr");
    if (!gipa) return 1;

    PFN_vkCreateInstance p_vkCreateInstance = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
    VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO, NULL, "poco-adreno-probe", 1, "adreno-vk", 1, VK_MAKE_API_VERSION(0,1,1,0) };
    VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, NULL, 0, &app, 0, NULL, 0, NULL };
    VkInstance inst = NULL;
    if (!p_vkCreateInstance || p_vkCreateInstance(&ici, NULL, &inst) != VK_SUCCESS) return 1;

    PFN_vkEnumeratePhysicalDevices p_enum = (PFN_vkEnumeratePhysicalDevices)gipa(inst, "vkEnumeratePhysicalDevices");
    PFN_vkGetPhysicalDeviceProperties p_props = (PFN_vkGetPhysicalDeviceProperties)gipa(inst, "vkGetPhysicalDeviceProperties");
    PFN_vkGetPhysicalDeviceQueueFamilyProperties p_qfp = (PFN_vkGetPhysicalDeviceQueueFamilyProperties)gipa(inst, "vkGetPhysicalDeviceQueueFamilyProperties");
    PFN_vkCreateDevice p_createDev = (PFN_vkCreateDevice)gipa(inst, "vkCreateDevice");
    PFN_vkGetDeviceProcAddr gdpa = (PFN_vkGetDeviceProcAddr)gipa(inst, "vkGetDeviceProcAddr");
    PFN_vkDestroyInstance p_destroyInst = (PFN_vkDestroyInstance)gipa(inst, "vkDestroyInstance");

    uint32_t count = 0;
    if (p_enum(inst, &count, NULL) != VK_SUCCESS || count == 0) return 2;

    VkPhysicalDevice devs[8];
    if (count > 8) count = 8;
    p_enum(inst, &count, devs);

    printf("Loader Vulkan  : %s\n", loader_path);
    int hw_idx = -1;
    for (uint32_t i = 0; i < count; i++) {
        VkPhysicalDeviceProperties pr;
        memset(&pr, 0, sizeof(pr));
        p_props(devs[i], &pr);
        printf("  [Vulkan %u] %s | vendor=0x%04x | device=0x%04x | tipo=%s | api=%u.%u.%u\n",
               i, pr.deviceName, pr.vendorID, pr.deviceID, dev_type_str(pr.deviceType),
               VK_API_VER_MAJOR(pr.apiVersion), VK_API_VER_MINOR(pr.apiVersion), VK_API_VER_PATCH(pr.apiVersion));
        if (pr.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU ||
            pr.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
            if (hw_idx < 0 || pr.vendorID == 0x5143) hw_idx = (int)i;
        }
    }

    if (hw_idx < 0) {
        fprintf(stderr, "[FALLO] Solo se detecto emulacion CPU (llvmpipe).\n");
        return 3;
    }

    uint32_t qcount = 0;
    p_qfp(devs[hw_idx], &qcount, NULL);
    VkQueueFamilyProperties *qprops = (VkQueueFamilyProperties*)calloc(qcount, sizeof(*qprops));
    p_qfp(devs[hw_idx], &qcount, qprops);
    uint32_t compute_qf = 0;
    int found_compute = 0;
    for (uint32_t q = 0; q < qcount; q++) {
        if (qprops[q].queueFlags & VK_QUEUE_COMPUTE_BIT) { compute_qf = q; found_compute = 1; break; }
    }
    free(qprops);
    if (!found_compute) return 4;

    float prio = 1.0f;
    VkDeviceQueueCreateInfo dqci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, NULL, 0, compute_qf, 1, &prio };
    VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, NULL, 0, 1, &dqci, 0, NULL, 0, NULL, NULL };
    VkDevice dev = NULL;
    if (p_createDev(devs[hw_idx], &dci, NULL, &dev) != VK_SUCCESS) return 5;

    printf("[OK] VkDevice Compute inicializado en GPU hardware indice %d (cola %u).\n", hw_idx, compute_qf);

    FILE *maps = fopen("/proc/self/maps", "r");
    if (maps) {
        char line[512], prev[512] = "";
        while (fgets(line, sizeof(line), maps)) {
            char *p = strchr(line, '/');
            if (p && (strstr(p, "vulkan") || strstr(p, "adreno") || strstr(p, "kgsl"))) {
                if (strcmp(p, prev) != 0) {
                    printf("  [maps] %s", p);
                    snprintf(prev, sizeof(prev), "%s", p);
                }
            }
        }
        fclose(maps);
    }

    DIR *fddir = opendir("/proc/self/fd");
    if (fddir) {
        struct dirent *de;
        while ((de = readdir(fddir)) != NULL) {
            char pbuf[512], lbuf[256];
            snprintf(pbuf, sizeof(pbuf), "/proc/self/fd/%s", de->d_name);
            ssize_t n = readlink(pbuf, lbuf, sizeof(lbuf) - 1);
            if (n > 0) {
                lbuf[n] = '\0';
                if (strstr(lbuf, "kgsl") || strstr(lbuf, "dri")) printf("  [fd %s] -> %s\n", de->d_name, lbuf);
            }
        }
        closedir(fddir);
    }

    PFN_vkDestroyDevice p_destroyDev = (PFN_vkDestroyDevice)gdpa(dev, "vkDestroyDevice");
    if (p_destroyDev) p_destroyDev(dev, NULL);
    if (p_destroyInst) p_destroyInst(inst, NULL);
    dlclose(lib);
    return 0;
}
PROBE_VK_EOF

# 1B. Sonda OpenCL Nativa (Android 16 Bionic 'sphal' -> /vendor/lib64/libOpenCL.so)
cat <<'PROBE_CL_EOF' > "$SRC_DIR/cl_adreno_probe.c"
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>

#ifdef __ANDROID__
#include <android/dlext.h>
#else
struct android_namespace_t;
typedef struct {
    uint64_t flags;
    void*   reserved_addr;
    size_t  reserved_size;
    int     relro_fd;
    int     library_fd;
    int64_t library_fd_offset;
    struct android_namespace_t* library_namespace;
} android_dlextinfo;
#define ANDROID_DLEXT_USE_NAMESPACE 0x200ULL
#endif

typedef int32_t  cl_int;
typedef uint32_t cl_uint;
typedef uint64_t cl_ulong;
typedef uint64_t cl_bitfield;
typedef cl_bitfield cl_device_type;
typedef cl_bitfield cl_command_queue_properties;
typedef cl_bitfield cl_mem_flags;
typedef void* cl_platform_id;
typedef void* cl_device_id;
typedef void* cl_context;
typedef void* cl_command_queue;
typedef void* cl_mem;
typedef void* cl_program;
typedef void* cl_kernel;
typedef void* cl_event;

#define CL_SUCCESS 0
#define CL_DEVICE_TYPE_GPU (1ULL << 2)
#define CL_PLATFORM_NAME   0x0902
#define CL_PLATFORM_VENDOR 0x0903
#define CL_DEVICE_NAME     0x102B
#define CL_DRIVER_VERSION  0x102D
#define CL_DEVICE_VERSION  0x102F
#define CL_DEVICE_GLOBAL_MEM_SIZE 0x101F
#define CL_MEM_READ_WRITE  (1ULL << 0)
#define CL_MEM_COPY_HOST_PTR (1ULL << 5)

typedef cl_int (*pfn_clGetPlatformIDs)(cl_uint, cl_platform_id*, cl_uint*);
typedef cl_int (*pfn_clGetPlatformInfo)(cl_platform_id, cl_uint, size_t, void*, size_t*);
typedef cl_int (*pfn_clGetDeviceIDs)(cl_platform_id, cl_device_type, cl_uint, cl_device_id*, cl_uint*);
typedef cl_int (*pfn_clGetDeviceInfo)(cl_device_id, cl_uint, size_t, void*, size_t*);
typedef cl_context (*pfn_clCreateContext)(const void*, cl_uint, const cl_device_id*, void*, void*, cl_int*);
typedef cl_command_queue (*pfn_clCreateCommandQueue)(cl_context, cl_device_id, cl_command_queue_properties, cl_int*);
typedef cl_mem (*pfn_clCreateBuffer)(cl_context, cl_mem_flags, size_t, void*, cl_int*);
typedef cl_program (*pfn_clCreateProgramWithSource)(cl_context, cl_uint, const char**, const size_t*, cl_int*);
typedef cl_int (*pfn_clBuildProgram)(cl_program, cl_uint, const cl_device_id*, const char*, void*, void*);
typedef cl_kernel (*pfn_clCreateKernel)(cl_program, const char*, cl_int*);
typedef cl_int (*pfn_clSetKernelArg)(cl_kernel, cl_uint, size_t, const void*);
typedef cl_int (*pfn_clEnqueueNDRangeKernel)(cl_command_queue, cl_kernel, cl_uint, const size_t*, const size_t*, const size_t*, cl_uint, const cl_event*, cl_event*);
typedef cl_int (*pfn_clEnqueueReadBuffer)(cl_command_queue, cl_mem, cl_uint, size_t, size_t, void*, cl_uint, const cl_event*, cl_event*);
typedef cl_int (*pfn_clFinish)(cl_command_queue);

static void *load_qualcomm_opencl(const char **method_out) {
    const char *ovr = getenv("GGML_OPENCL_LOADER_PATH");
    if (ovr && ovr[0]) {
        void *h = dlopen(ovr, RTLD_NOW | RTLD_LOCAL);
        if (h && dlsym(h, "clGetPlatformIDs")) {
            *method_out = ovr;
            return h;
        }
    }

    typedef struct android_namespace_t* (*get_ns_fn)(const char*);
    typedef void* (*dlopen_ext_fn)(const char*, int, const android_dlextinfo*);
    get_ns_fn get_ns = (get_ns_fn)dlsym(RTLD_DEFAULT, "__loader_android_get_exported_namespace");
    dlopen_ext_fn open_ext = (dlopen_ext_fn)dlsym(RTLD_DEFAULT, "android_dlopen_ext");

    if (get_ns && open_ext) {
        struct android_namespace_t *sphal = get_ns("sphal");
        if (!sphal) sphal = get_ns("vendor");
        if (sphal) {
            android_dlextinfo ext;
            memset(&ext, 0, sizeof(ext));
            ext.flags = ANDROID_DLEXT_USE_NAMESPACE;
            ext.library_namespace = sphal;

            const char *adreno_paths[] = { "/vendor/lib64/libOpenCL_adreno.so", "/system/vendor/lib64/libOpenCL_adreno.so" };
            for (size_t i = 0; i < 2; i++) {
                void *drv = open_ext(adreno_paths[i], RTLD_NOW | RTLD_LOCAL, &ext);
                if (drv) {
                    typedef int (*init_fn)(void);
                    init_fn init_drv = (init_fn)dlsym(drv, "InitOpenCLDriver");
                    if (init_drv) (void)init_drv();
                    break;
                }
            }

            const char *cl_paths[] = { "/vendor/lib64/libOpenCL.so", "/system/vendor/lib64/libOpenCL.so", "/vendor/lib64/libOpenCL_adreno.so" };
            for (size_t i = 0; i < 3; i++) {
                void *h = open_ext(cl_paths[i], RTLD_NOW | RTLD_LOCAL, &ext);
                if (h && dlsym(h, "clGetPlatformIDs")) {
                    *method_out = "android_dlopen_ext(sphal) -> /vendor/lib64/libOpenCL.so";
                    return h;
                }
            }
        }
    }

    void *vndk = dlopen("/system/lib64/libvndksupport.so", RTLD_NOW | RTLD_LOCAL);
    if (vndk) {
        typedef void* (*load_sphal_fn)(const char*, int);
        load_sphal_fn load_sphal = (load_sphal_fn)dlsym(vndk, "android_load_sphal_library");
        if (load_sphal) {
            void *drv = load_sphal("libOpenCL_adreno.so", RTLD_NOW | RTLD_LOCAL);
            if (drv) {
                typedef int (*init_fn)(void);
                init_fn init_drv = (init_fn)dlsym(drv, "InitOpenCLDriver");
                if (init_drv) (void)init_drv();
            }
            void *h = load_sphal("libOpenCL.so", RTLD_NOW | RTLD_LOCAL);
            if (h && dlsym(h, "clGetPlatformIDs")) {
                *method_out = "libvndksupport(android_load_sphal_library)";
                return h;
            }
        }
    }

    void *direct = dlopen("libOpenCL.so", RTLD_NOW | RTLD_LOCAL);
    if (direct && dlsym(direct, "clGetPlatformIDs")) {
        *method_out = "dlopen(libOpenCL.so)";
        return direct;
    }
    return NULL;
}

int main(void) {
    const char *method = "none";
    void *lib = load_qualcomm_opencl(&method);
    if (!lib) {
        fprintf(stderr, "[OPENCL-PROBE] No se pudo cargar libOpenCL.so: %s\n", dlerror());
        return 1;
    }

    pfn_clGetPlatformIDs f_plat = (pfn_clGetPlatformIDs)dlsym(lib, "clGetPlatformIDs");
    pfn_clGetPlatformInfo f_pinfo = (pfn_clGetPlatformInfo)dlsym(lib, "clGetPlatformInfo");
    pfn_clGetDeviceIDs f_devs = (pfn_clGetDeviceIDs)dlsym(lib, "clGetDeviceIDs");
    pfn_clGetDeviceInfo f_dinfo = (pfn_clGetDeviceInfo)dlsym(lib, "clGetDeviceInfo");
    pfn_clCreateContext f_ctx = (pfn_clCreateContext)dlsym(lib, "clCreateContext");
    pfn_clCreateCommandQueue f_q = (pfn_clCreateCommandQueue)dlsym(lib, "clCreateCommandQueue");
    pfn_clCreateBuffer f_buf = (pfn_clCreateBuffer)dlsym(lib, "clCreateBuffer");
    pfn_clCreateProgramWithSource f_prog = (pfn_clCreateProgramWithSource)dlsym(lib, "clCreateProgramWithSource");
    pfn_clBuildProgram f_build = (pfn_clBuildProgram)dlsym(lib, "clBuildProgram");
    pfn_clCreateKernel f_kern = (pfn_clCreateKernel)dlsym(lib, "clCreateKernel");
    pfn_clSetKernelArg f_arg = (pfn_clSetKernelArg)dlsym(lib, "clSetKernelArg");
    pfn_clEnqueueNDRangeKernel f_nd = (pfn_clEnqueueNDRangeKernel)dlsym(lib, "clEnqueueNDRangeKernel");
    pfn_clEnqueueReadBuffer f_read = (pfn_clEnqueueReadBuffer)dlsym(lib, "clEnqueueReadBuffer");
    pfn_clFinish f_fin = (pfn_clFinish)dlsym(lib, "clFinish");

    cl_uint nplat = 0;
    cl_platform_id plats[8];
    if (!f_plat || f_plat(8, plats, &nplat) != CL_SUCCESS || nplat == 0) {
        fprintf(stderr, "[OPENCL-PROBE] 0 plataformas OpenCL disponibles.\n");
        return 2;
    }

    printf("Metodo OpenCL  : %s\n", method);
    cl_device_id chosen = NULL;
    for (cl_uint i = 0; i < nplat; i++) {
        char pname[128] = "", pvend[128] = "";
        f_pinfo(plats[i], CL_PLATFORM_NAME, sizeof(pname), pname, NULL);
        f_pinfo(plats[i], CL_PLATFORM_VENDOR, sizeof(pvend), pvend, NULL);
        if (strstr(pname, "llvmpipe") || strstr(pvend, "Mesa")) continue;

        cl_uint ndev = 0;
        cl_device_id devs[8];
        if (f_devs(plats[i], CL_DEVICE_TYPE_GPU, 8, devs, &ndev) == CL_SUCCESS && ndev > 0) {
            for (cl_uint j = 0; j < ndev; j++) {
                char dname[128] = "", dver[128] = "", drv[128] = "";
                cl_ulong mem = 0;
                f_dinfo(devs[j], CL_DEVICE_NAME, sizeof(dname), dname, NULL);
                f_dinfo(devs[j], CL_DEVICE_VERSION, sizeof(dver), dver, NULL);
                f_dinfo(devs[j], CL_DRIVER_VERSION, sizeof(drv), drv, NULL);
                f_dinfo(devs[j], CL_DEVICE_GLOBAL_MEM_SIZE, sizeof(mem), &mem, NULL);
                printf("  [OpenCL GPU] %s | %s | %s | VRAM=%.0f MiB\n",
                       dname, dver, drv, (double)mem / (1024.0 * 1024.0));
                if (!strstr(dname, "llvmpipe") && chosen == NULL) chosen = devs[j];
            }
        }
    }

    if (!chosen) return 3;

    cl_int err = 0;
    cl_context ctx = f_ctx(NULL, 1, &chosen, NULL, NULL, &err);
    cl_command_queue q = f_q(ctx, chosen, 0, &err);
    float a[4] = {10.f, 20.f, 30.f, 40.f}, b[4] = {32.f, 22.f, 12.f, 2.f}, c[4] = {0};
    cl_mem ba = f_buf(ctx, CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR, sizeof(a), a, &err);
    cl_mem bb = f_buf(ctx, CL_MEM_READ_WRITE | CL_MEM_COPY_HOST_PTR, sizeof(b), b, &err);
    cl_mem bc = f_buf(ctx, CL_MEM_READ_WRITE, sizeof(c), NULL, &err);
    const char *src = "__kernel void vadd(__global const float* a, __global const float* b, __global float* c){ int i=get_global_id(0); c[i]=a[i]+b[i]; }";
    size_t slen = strlen(src);
    cl_program prog = f_prog(ctx, 1, &src, &slen, &err);
    if (f_build(prog, 1, &chosen, "", NULL, NULL) != CL_SUCCESS) return 4;
    cl_kernel kern = f_kern(prog, "vadd", &err);
    f_arg(kern, 0, sizeof(cl_mem), &ba);
    f_arg(kern, 1, sizeof(cl_mem), &bb);
    f_arg(kern, 2, sizeof(cl_mem), &bc);
    size_t gws = 4;
    f_nd(q, kern, 1, NULL, &gws, NULL, 0, NULL, NULL);
    f_fin(q);
    f_read(q, bc, 1, 0, sizeof(c), c, 0, NULL, NULL);
    if (c[0] != 42.0f || c[3] != 42.0f) return 5;

    printf("[OK] Kernel de computo OpenCL ejecutado fisicamente en Adreno (42.0 verificado).\n");
    DIR *fddir = opendir("/proc/self/fd");
    if (fddir) {
        struct dirent *de;
        while ((de = readdir(fddir)) != NULL) {
            char pbuf[512], lbuf[256];
            snprintf(pbuf, sizeof(pbuf), "/proc/self/fd/%s", de->d_name);
            ssize_t n = readlink(pbuf, lbuf, sizeof(lbuf) - 1);
            if (n > 0) {
                lbuf[n] = '\0';
                if (strstr(lbuf, "kgsl")) printf("  [fd %s] -> %s\n", de->d_name, lbuf);
            }
        }
        closedir(fddir);
    }
    return 0;
}
PROBE_CL_EOF

# 1C. Sonda OpenGL ES 3.2 (EGL Headless Pbuffer -> /system/lib64/libGLESv3.so)
cat <<'PROBE_GLES_EOF' > "$SRC_DIR/gles_adreno_probe.c"
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>

typedef int32_t EGLint;
typedef unsigned int EGLBoolean;
typedef void* EGLDisplay;
typedef void* EGLConfig;
typedef void* EGLContext;
typedef void* EGLSurface;
typedef unsigned int GLenum;

#define EGL_DEFAULT_DISPLAY ((void*)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_DISPLAY ((EGLDisplay)0)
#define EGL_SURFACE_TYPE 0x3033
#define EGL_PBUFFER_BIT 0x0001
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_OPENGL_ES3_BIT 0x0040
#define EGL_NONE 0x3038
#define EGL_WIDTH 0x3057
#define EGL_HEIGHT 0x3056
#define EGL_CONTEXT_CLIENT_VERSION 0x3098
#define GL_VENDOR 0x1F00
#define GL_RENDERER 0x1F01
#define GL_VERSION 0x1F02

int main(void) {
    void *egl = dlopen("/system/lib64/libEGL.so", RTLD_NOW | RTLD_LOCAL);
    void *gles = dlopen("/system/lib64/libGLESv3.so", RTLD_NOW | RTLD_LOCAL);
    if (!egl || !gles) return 1;
    EGLDisplay (*f_getDisplay)(void*) = (EGLDisplay (*)(void*))dlsym(egl, "eglGetDisplay");
    EGLBoolean (*f_init)(EGLDisplay, EGLint*, EGLint*) = (EGLBoolean (*)(EGLDisplay, EGLint*, EGLint*))dlsym(egl, "eglInitialize");
    EGLBoolean (*f_choose)(EGLDisplay, const EGLint*, EGLConfig*, EGLint, EGLint*) = (EGLBoolean (*)(EGLDisplay, const EGLint*, EGLConfig*, EGLint, EGLint*))dlsym(egl, "eglChooseConfig");
    EGLSurface (*f_pbuf)(EGLDisplay, EGLConfig, const EGLint*) = (EGLSurface (*)(EGLDisplay, EGLConfig, const EGLint*))dlsym(egl, "eglCreatePbufferSurface");
    EGLContext (*f_ctx)(EGLDisplay, EGLConfig, EGLContext, const EGLint*) = (EGLContext (*)(EGLDisplay, EGLConfig, EGLContext, const EGLint*))dlsym(egl, "eglCreateContext");
    EGLBoolean (*f_make)(EGLDisplay, EGLSurface, EGLSurface, EGLContext) = (EGLBoolean (*)(EGLDisplay, EGLSurface, EGLSurface, EGLContext))dlsym(egl, "eglMakeCurrent");
    const unsigned char* (*f_str)(GLenum) = (const unsigned char* (*)(GLenum))dlsym(gles, "glGetString");

    EGLDisplay dpy = f_getDisplay(EGL_DEFAULT_DISPLAY);
    EGLint maj = 0, min = 0;
    if (dpy == EGL_NO_DISPLAY || !f_init(dpy, &maj, &min)) return 2;
    const EGLint cfg_att[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE };
    EGLConfig cfg = NULL; EGLint ncfg = 0;
    f_choose(dpy, cfg_att, &cfg, 1, &ncfg);
    const EGLint pb_att[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
    EGLSurface surf = f_pbuf(dpy, cfg, pb_att);
    const EGLint ctx_att[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
    EGLContext ctx = f_ctx(dpy, cfg, EGL_NO_CONTEXT, ctx_att);
    if (!f_make(dpy, surf, surf, ctx)) return 3;

    printf("  [OpenGL ES] Vendor=%s | Renderer=%s | Version=%s\n",
           (const char*)f_str(GL_VENDOR), (const char*)f_str(GL_RENDERER), (const char*)f_str(GL_VERSION));
    printf("  [Diagnostico] OpenGL ES 3.2 activo en Adreno, pero GGML/Ollama no implementa backend GLES (sin backend GGML GLES en esta version); se activan Vulkan + OpenCL nativos.\n");
    return 0;
}
PROBE_GLES_EOF

clang -O2 -std=c11 "$SRC_DIR/vk_adreno_probe.c"   -ldl -o "$EXP_DIR/bin/vk_adreno_probe"
clang -O2 -std=c11 "$SRC_DIR/cl_adreno_probe.c"   -ldl -o "$EXP_DIR/bin/cl_adreno_probe"
clang -O2 -std=c11 "$SRC_DIR/gles_adreno_probe.c" -ldl -o "$EXP_DIR/bin/gles_adreno_probe"

info "1A) Verificando Vulkan Hardware Adreno 840:"
"$EXP_DIR/bin/vk_adreno_probe" "/system/lib64/libvulkan.so" | tee "$LOG_DIR/01-vk-probe.txt"
ok "Vulkan Adreno 840 + /dev/kgsl-3d0 confirmado."

ENABLE_OPENCL_BUILD=0
OPENCL_LOADER_OVERRIDE=""
info "1B) Verificando OpenCL Hardware Adreno 840 (vía Android 16 'sphal' namespace):"
if "$EXP_DIR/bin/cl_adreno_probe" | tee "$LOG_DIR/01-cl-probe.txt"; then
  ENABLE_OPENCL_BUILD=1
  ok "Qualcomm OpenCL 3.0 en Adreno 840 confirmado sin root."
else
  warn "OpenCL vía sphal directo no respondió; se intentará puente local aislado si /vendor/lib64/libOpenCL.so es legible."
fi

info "1C) Verificando OpenGL ES 3.2 (diagnóstico de capacidades gráficas):"
"$EXP_DIR/bin/gles_adreno_probe" | tee "$LOG_DIR/01-gles-probe.txt" || true

# --------------------------- 2. FASE 2: Herramientas de compilación -----------
if [ "${SOLO_PRUEBAS}" -eq 0 ]; then
  NEED_BUILD_DEPS=0
  for cmd in clang clang++ cmake ninja go glslc patchelf git curl python3 make pkg-config; do
    command -v "$cmd" >/dev/null 2>&1 || NEED_BUILD_DEPS=1
  done
  [ -f "$PREFIX/include/vulkan/vulkan.h" ] || NEED_BUILD_DEPS=1
  [ -f "$PREFIX/include/CL/cl.h" ] || NEED_BUILD_DEPS=1
  [ -d "$PREFIX/share/cmake/SPIRV-Headers" ] || [ -d "$PREFIX/lib/cmake/SPIRV-Headers" ] || NEED_BUILD_DEPS=1

  if [ "${NEED_BUILD_DEPS}" -eq 1 ]; then
    info "FASE 2/5 — Instalando dependencias de compilación (incluyendo opencl-headers y patchelf)..."
    pkg update -y
    pkg install -y clang git curl python cmake ninja golang shaderc vulkan-headers spirv-headers opencl-headers patchelf llvm lld libandroid-spawn make pkg-config
  else
    ok "FASE 2/5 — Toolchain completo (Vulkan + OpenCL + Go + Ninja) ya instalado."
  fi

  # Si OpenCL sphal directo no abrió en 1B pero /vendor/lib64/libOpenCL.so es legible, crear puente aislado con patchelf
  if [ "${ENABLE_OPENCL_BUILD}" -eq 0 ] && [ -r "/vendor/lib64/libOpenCL.so" ]; then
    info "Construyendo puente aislado de librerías Qualcomm OpenCL en $EXP_DIR/lib/adreno-opencl/..."
    mkdir -p "$EXP_DIR/lib/adreno-opencl"
    for vlib in libOpenCL.so libOpenCL_adreno.so libCB.so libgsl.so libllvm-qgl.so libllvm-qcom.so; do
      if [ -r "/vendor/lib64/$vlib" ]; then
        cp -f "/vendor/lib64/$vlib" "$EXP_DIR/lib/adreno-opencl/$vlib"
        chmod 755 "$EXP_DIR/lib/adreno-opencl/$vlib"
        patchelf --set-rpath '$ORIGIN' "$EXP_DIR/lib/adreno-opencl/$vlib" 2>/dev/null || true
      fi
    done
    if LD_LIBRARY_PATH="/system/lib64:$EXP_DIR/lib/adreno-opencl:$PREFIX/lib" \
       GGML_OPENCL_LOADER_PATH="$EXP_DIR/lib/adreno-opencl/libOpenCL.so" \
       "$EXP_DIR/bin/cl_adreno_probe" | tee -a "$LOG_DIR/01-cl-probe.txt"; then
      ENABLE_OPENCL_BUILD=1
      OPENCL_LOADER_OVERRIDE="$EXP_DIR/lib/adreno-opencl/libOpenCL.so"
      ok "OpenCL Adreno 840 activado mediante puente aislado patchelf."
    fi
  fi

  # ------------------------- 3. FASE 3: Código fuente y parches v2 ------------
  OLLAMA_TAG="v0.40.16"
  OLLAMA_SRC="$SRC_DIR/ollama"
  LLAMA_SRC="$SRC_DIR/llama-cpp"
  BUILD_DIR="$EXP_DIR/build-llama-vk"

  if [ ! -d "$OLLAMA_SRC/.git" ]; then
    info "FASE 3/5 — Clonando Ollama ${OLLAMA_TAG}..."
    git clone --depth=1 --branch "${OLLAMA_TAG}" https://github.com/ollama/ollama.git "$OLLAMA_SRC"
  else
    ok "Código fuente de Ollama ${OLLAMA_TAG} ya presente."
  fi

  LLAMA_TAG="$(tr -d '[:space:]' < "$OLLAMA_SRC/LLAMA_CPP_VERSION")"
  if [ ! -d "$LLAMA_SRC/.git" ]; then
    info "Clonando llama.cpp (${LLAMA_TAG})..."
    git clone --depth=1 --branch "${LLAMA_TAG}" https://github.com/ggml-org/llama.cpp.git "$LLAMA_SRC"
  else
    ok "Código fuente de llama.cpp (${LLAMA_TAG}) ya presente."
  fi

  if [ ! -f "$PATCH_DIR/30821.patch" ]; then
    info "Descargando parche oficial Qualcomm Adreno 840 PR #30821..."
    curl -fsSL "https://patch-diff.githubusercontent.com/raw/ggml-org/llama.cpp/pull/30821.patch" -o "$PATCH_DIR/30821.patch"
  fi

  # Aplicar parches v2 sobre llama.cpp (anti-signal-9 + depfile .d + Adreno Vulkan + Adreno OpenCL SPHAL)
  if [ ! -f "$LLAMA_SRC/.poco_adreno840_v2_patched" ]; then
    info "Aplicando parches v2 (Vulkan anti-signal-9 + depfile fix + Qualcomm OpenCL SPHAL)..."
    (
      cd "$LLAMA_SRC"
      git checkout -- .
      git clean -fd

      # 1) Hooks de compatibilidad de Ollama 0.40.16
      git apply "$OLLAMA_SRC/llama/compat/001-llama-cpp-hooks.patch"

      # 2) Parche Qualcomm PR #30821 (fix shaders 8-bit vectors unpack8/pack32 en Adreno 840)
      python3 - <<'PY'
p = "ggml/src/ggml-vulkan/ggml-vulkan-types.h"
s = open(p, "r", encoding="utf-8").read()
if "bool avoid_8bit_vectors;" not in s:
    assert "bool disable_fusion;" in s
    s = s.replace("bool disable_fusion;", "bool disable_fusion;\n    bool avoid_8bit_vectors;", 1)
    open(p, "w", encoding="utf-8").write(s)
PY
      git apply -C1 --exclude=ggml/src/ggml-vulkan/ggml-vulkan-types.h "$PATCH_DIR/30821.patch"

      # 3) Parches Vulkan v2 + OpenCL SPHAL v2
      python3 - <<'PY'
# --- A. Vulkan PR #30829 (FlashAttention hsk > 128 en Qualcomm Adreno) ---
p_vk = "ggml/src/ggml-vulkan/ggml-vulkan.cpp"
s_vk = open(p_vk, "r", encoding="utf-8").read()
needle = "    // On AMD RDNA, for small head sizes and big batch size"
fix = (
    "    // Qualcomm Adreno PR #30829: cap rows at 8 when hsk/hsv > 128 to prevent scratch spill\n"
    "    if (device->vendor_id == VK_VENDOR_ID_QUALCOMM && (hsk > 128 || hsv > 128)) {\n"
    "        result.block_rows = std::min(result.block_rows, 8u);\n"
    "    }\n\n"
)
assert needle in s_vk
s_vk = s_vk.replace(needle, fix + needle, 1)
open(p_vk, "w", encoding="utf-8").write(s_vk)

# --- B. Perfil GLSL Adreno 840 (conservar GL_EXT_integer_dot_product; omitir coopmat/bf16/fp4) ---
p_cm = "ggml/src/ggml-vulkan/CMakeLists.txt"
s_cm = open(p_cm, "r", encoding="utf-8").read()
anchor = "function(test_shader_extension_support EXTENSION_NAME TEST_SHADER_FILE RESULT_VARIABLE)\n"
guard = (
    anchor +
    '    if (NOT "${EXTENSION_NAME}" STREQUAL "GL_EXT_integer_dot_product")\n'
    '        message(STATUS "Adreno 840 profile: skipping ${EXTENSION_NAME}")\n'
    '        set(${RESULT_VARIABLE} OFF PARENT_SCOPE)\n'
    '        return()\n'
    '    endif()\n'
)
assert anchor in s_cm
s_cm = s_cm.replace(anchor, guard, 1)
open(p_cm, "w", encoding="utf-8").write(s_cm)

# --- C. vulkan-shaders-gen.cpp:
#     1) COOPMAT2 && 0
#     2) Limitar N = 2u subprocesos glslc por generador (evita el límite de 32 procesos fantasma / signal 9 en Android 16)
#     3) Emitir siempre depfile .d válido cuando se omiten variantes _cm1/_cm2 (elimina los CMake Warning)
p_gen = "ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp"
s_gen = open(p_gen, "r", encoding="utf-8").read()
s_gen = s_gen.replace(
    "#if defined(GGML_VULKAN_COOPMAT2_GLSLC_SUPPORT)",
    "#if defined(GGML_VULKAN_COOPMAT2_GLSLC_SUPPORT) && 0"
)
old_slot = "    uint32_t N = std::max(1u, std::min(16u, std::thread::hardware_concurrency()));"
new_slot = "    uint32_t N = 2u; // Android 16 Termux: evita superar max_phantom_processes=32 (SIGKILL signal 9)"
assert old_slot in s_gen
s_gen = s_gen.replace(old_slot, new_slot, 1)

old_write = '    if (target_cpp != "") {\n        write_binary_file(target_cpp, src.str());\n    }'
new_write = (
    '    if (target_cpp != "") {\n'
    '        write_binary_file(target_cpp, src.str());\n'
    '        if (generate_dep_file && input_filepath != "") {\n'
    '            write_binary_file(target_cpp + ".d", target_cpp + ": " + input_filepath + "\\n");\n'
    '        }\n'
    '    }'
)
assert old_write in s_gen
s_gen = s_gen.replace(old_write, new_write, 1)
open(p_gen, "w", encoding="utf-8").write(s_gen)

# --- D. Qualcomm Adreno OpenCL SPHAL Bridge (sin root, sin ocl-icd, sin llvmpipe) ---
sphal_h = r'''#pragma once

#include <CL/cl.h>

#define GGML_OPENCL_SPHAL_FUNCTIONS(X) \
    X(clBuildProgram) \
    X(clCreateBuffer) \
    X(clCreateBufferWithProperties) \
    X(clCreateCommandQueue) \
    X(clCreateContext) \
    X(clCreateImage) \
    X(clCreateKernel) \
    X(clCreateProgramWithBinary) \
    X(clCreateProgramWithSource) \
    X(clCreateSubBuffer) \
    X(clEnqueueBarrierWithWaitList) \
    X(clEnqueueCopyBuffer) \
    X(clEnqueueFillBuffer) \
    X(clEnqueueMapBuffer) \
    X(clEnqueueMarkerWithWaitList) \
    X(clEnqueueNDRangeKernel) \
    X(clEnqueueReadBuffer) \
    X(clEnqueueUnmapMemObject) \
    X(clEnqueueWriteBuffer) \
    X(clFinish) \
    X(clFlush) \
    X(clGetDeviceIDs) \
    X(clGetDeviceInfo) \
    X(clGetEventProfilingInfo) \
    X(clGetKernelInfo) \
    X(clGetKernelSubGroupInfo) \
    X(clGetKernelWorkGroupInfo) \
    X(clGetPlatformIDs) \
    X(clGetPlatformInfo) \
    X(clGetProgramBuildInfo) \
    X(clGetProgramInfo) \
    X(clReleaseEvent) \
    X(clReleaseKernel) \
    X(clReleaseMemObject) \
    X(clReleaseProgram) \
    X(clSetKernelArg) \
    X(clWaitForEvents)

struct ggml_opencl_sphal_dispatch {
#define GGML_OPENCL_SPHAL_FIELD(name) decltype(&::name) name;
    GGML_OPENCL_SPHAL_FUNCTIONS(GGML_OPENCL_SPHAL_FIELD)
#undef GGML_OPENCL_SPHAL_FIELD
};

extern ggml_opencl_sphal_dispatch ggml_opencl_sphal;
bool ggml_opencl_sphal_init();

#ifndef GGML_OPENCL_SPHAL_NO_REMAP
#define clBuildProgram ggml_opencl_sphal.clBuildProgram
#define clCreateBuffer ggml_opencl_sphal.clCreateBuffer
#define clCreateBufferWithProperties ggml_opencl_sphal.clCreateBufferWithProperties
#define clCreateCommandQueue ggml_opencl_sphal.clCreateCommandQueue
#define clCreateContext ggml_opencl_sphal.clCreateContext
#define clCreateImage ggml_opencl_sphal.clCreateImage
#define clCreateKernel ggml_opencl_sphal.clCreateKernel
#define clCreateProgramWithBinary ggml_opencl_sphal.clCreateProgramWithBinary
#define clCreateProgramWithSource ggml_opencl_sphal.clCreateProgramWithSource
#define clCreateSubBuffer ggml_opencl_sphal.clCreateSubBuffer
#define clEnqueueBarrierWithWaitList ggml_opencl_sphal.clEnqueueBarrierWithWaitList
#define clEnqueueCopyBuffer ggml_opencl_sphal.clEnqueueCopyBuffer
#define clEnqueueFillBuffer ggml_opencl_sphal.clEnqueueFillBuffer
#define clEnqueueMapBuffer ggml_opencl_sphal.clEnqueueMapBuffer
#define clEnqueueMarkerWithWaitList ggml_opencl_sphal.clEnqueueMarkerWithWaitList
#define clEnqueueNDRangeKernel ggml_opencl_sphal.clEnqueueNDRangeKernel
#define clEnqueueReadBuffer ggml_opencl_sphal.clEnqueueReadBuffer
#define clEnqueueUnmapMemObject ggml_opencl_sphal.clEnqueueUnmapMemObject
#define clEnqueueWriteBuffer ggml_opencl_sphal.clEnqueueWriteBuffer
#define clFinish ggml_opencl_sphal.clFinish
#define clFlush ggml_opencl_sphal.clFlush
#define clGetDeviceIDs ggml_opencl_sphal.clGetDeviceIDs
#define clGetDeviceInfo ggml_opencl_sphal.clGetDeviceInfo
#define clGetEventProfilingInfo ggml_opencl_sphal.clGetEventProfilingInfo
#define clGetKernelInfo ggml_opencl_sphal.clGetKernelInfo
#define clGetKernelSubGroupInfo ggml_opencl_sphal.clGetKernelSubGroupInfo
#define clGetKernelWorkGroupInfo ggml_opencl_sphal.clGetKernelWorkGroupInfo
#define clGetPlatformIDs ggml_opencl_sphal.clGetPlatformIDs
#define clGetPlatformInfo ggml_opencl_sphal.clGetPlatformInfo
#define clGetProgramBuildInfo ggml_opencl_sphal.clGetProgramBuildInfo
#define clGetProgramInfo ggml_opencl_sphal.clGetProgramInfo
#define clReleaseEvent ggml_opencl_sphal.clReleaseEvent
#define clReleaseKernel ggml_opencl_sphal.clReleaseKernel
#define clReleaseMemObject ggml_opencl_sphal.clReleaseMemObject
#define clReleaseProgram ggml_opencl_sphal.clReleaseProgram
#define clSetKernelArg ggml_opencl_sphal.clSetKernelArg
#define clWaitForEvents ggml_opencl_sphal.clWaitForEvents
#endif
'''
open("ggml/src/ggml-opencl/opencl-sphal.h", "w", encoding="utf-8").write(sphal_h)

sphal_cpp = r'''#define CL_TARGET_OPENCL_VERSION GGML_OPENCL_TARGET_VERSION
#define CL_USE_DEPRECATED_OPENCL_1_2_APIS
#define GGML_OPENCL_SPHAL_NO_REMAP

#include "opencl-sphal.h"
#include "ggml-impl.h"

#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <mutex>

#ifdef __ANDROID__
#include <android/dlext.h>
#else
struct android_namespace_t;
typedef struct {
    uint64_t flags;
    void*   reserved_addr;
    size_t  reserved_size;
    int     relro_fd;
    int     library_fd;
    int64_t library_fd_offset;
    struct android_namespace_t* library_namespace;
} android_dlextinfo;
#define ANDROID_DLEXT_USE_NAMESPACE 0x200ULL
#endif

ggml_opencl_sphal_dispatch ggml_opencl_sphal = {};

static void * try_open_qualcomm_opencl() {
    const char * override_lib = getenv("GGML_OPENCL_LOADER_PATH");
    if (override_lib && override_lib[0]) {
        void * h = dlopen(override_lib, RTLD_NOW | RTLD_LOCAL);
        if (h && dlsym(h, "clGetPlatformIDs")) {
            GGML_LOG_INFO("ggml_opencl: loaded override OpenCL '%s'\n", override_lib);
            return h;
        }
    }

    using get_ns_fn = android_namespace_t * (*)(const char *);
    using dlopen_ext_fn = void * (*)(const char *, int, const android_dlextinfo *);
    auto get_ns = reinterpret_cast<get_ns_fn>(dlsym(RTLD_DEFAULT, "__loader_android_get_exported_namespace"));
    auto open_ext = reinterpret_cast<dlopen_ext_fn>(dlsym(RTLD_DEFAULT, "android_dlopen_ext"));

    if (get_ns && open_ext) {
        android_namespace_t * sphal = get_ns("sphal");
        if (!sphal) sphal = get_ns("vendor");
        if (sphal) {
            android_dlextinfo ext = {};
            ext.flags = ANDROID_DLEXT_USE_NAMESPACE;
            ext.library_namespace = sphal;

            const char * adreno_libs[] = {
                "/vendor/lib64/libOpenCL_adreno.so",
                "/system/vendor/lib64/libOpenCL_adreno.so"
            };
            for (const char * p : adreno_libs) {
                void * drv = open_ext(p, RTLD_NOW | RTLD_LOCAL, &ext);
                if (drv) {
                    using init_fn = int (*)(void);
                    auto init_drv = reinterpret_cast<init_fn>(dlsym(drv, "InitOpenCLDriver"));
                    if (init_drv) {
                        int rc = init_drv();
                        GGML_LOG_INFO("ggml_opencl: sphal InitOpenCLDriver(%s) = %d\n", p, rc);
                    }
                    break;
                }
            }

            const char * cl_libs[] = {
                "/vendor/lib64/libOpenCL.so",
                "/system/vendor/lib64/libOpenCL.so",
                "/vendor/lib64/libOpenCL_adreno.so"
            };
            for (const char * p : cl_libs) {
                void * loader = open_ext(p, RTLD_NOW | RTLD_LOCAL, &ext);
                if (loader && dlsym(loader, "clGetPlatformIDs")) {
                    GGML_LOG_INFO("ggml_opencl: loaded Qualcomm OpenCL via Android sphal (%s)\n", p);
                    return loader;
                }
            }
        }
    }

    void * vndk = dlopen("/system/lib64/libvndksupport.so", RTLD_NOW | RTLD_LOCAL);
    if (vndk) {
        using load_sphal_fn = void * (*)(const char *, int);
        auto load_sphal = reinterpret_cast<load_sphal_fn>(dlsym(vndk, "android_load_sphal_library"));
        if (load_sphal) {
            void * drv = load_sphal("libOpenCL_adreno.so", RTLD_NOW | RTLD_LOCAL);
            if (drv) {
                using init_fn = int (*)(void);
                auto init_drv = reinterpret_cast<init_fn>(dlsym(drv, "InitOpenCLDriver"));
                if (init_drv) init_drv();
            }
            void * loader = load_sphal("libOpenCL.so", RTLD_NOW | RTLD_LOCAL);
            if (loader && dlsym(loader, "clGetPlatformIDs")) {
                GGML_LOG_INFO("ggml_opencl: loaded Qualcomm OpenCL via libvndksupport\n");
                return loader;
            }
        }
    }

    void * direct = dlopen("libOpenCL.so", RTLD_NOW | RTLD_LOCAL);
    if (direct && dlsym(direct, "clGetPlatformIDs")) {
        GGML_LOG_INFO("ggml_opencl: loaded OpenCL via direct SONAME libOpenCL.so\n");
        return direct;
    }

    GGML_LOG_ERROR("ggml_opencl: unable to load Qualcomm libOpenCL.so: %s\n", dlerror());
    return nullptr;
}

static bool ggml_opencl_sphal_load() {
    void * loader = try_open_qualcomm_opencl();
    if (!loader) return false;

    using get_ext_fn = void * (*)(const char *);
    auto get_ext = reinterpret_cast<get_ext_fn>(dlsym(loader, "clGetExtensionFunctionAddress"));

    ggml_opencl_sphal_dispatch dispatch = {};
#define GGML_OPENCL_SPHAL_RESOLVE(name) \
    dispatch.name = reinterpret_cast<decltype(dispatch.name)>(dlsym(loader, #name)); \
    if (!dispatch.name && get_ext) { \
        dispatch.name = reinterpret_cast<decltype(dispatch.name)>(get_ext(#name)); \
    } \
    if (!dispatch.name) { \
        GGML_LOG_ERROR("ggml_opencl: missing OpenCL symbol %s\n", #name); \
        return false; \
    }
    GGML_OPENCL_SPHAL_FUNCTIONS(GGML_OPENCL_SPHAL_RESOLVE)
#undef GGML_OPENCL_SPHAL_RESOLVE

    ggml_opencl_sphal = dispatch;
    return true;
}

bool ggml_opencl_sphal_init() {
    static std::once_flag once;
    static bool ready = false;
    std::call_once(once, [] { ready = ggml_opencl_sphal_load(); });
    return ready;
}
'''
open("ggml/src/ggml-opencl/opencl-sphal.cpp", "w", encoding="utf-8").write(sphal_cpp)

p_clcm = "ggml/src/ggml-opencl/CMakeLists.txt"
s_clcm = open(p_clcm, "r", encoding="utf-8").read()
s_clcm = s_clcm.replace(
    "find_package(OpenCL REQUIRED)",
    'option(GGML_OPENCL_USE_SPHAL "Load Qualcomm OpenCL via Android sphal" OFF)\n'
    'if (GGML_OPENCL_USE_SPHAL)\n'
    '    find_path(OpenCL_INCLUDE_DIRS NAMES CL/cl.h REQUIRED)\n'
    'else ()\n'
    '    find_package(OpenCL REQUIRED)\n'
    'endif ()',
    1
)
s_clcm = s_clcm.replace(
    "target_link_libraries(${TARGET_NAME} PRIVATE ${OpenCL_LIBRARIES})",
    'if (GGML_OPENCL_USE_SPHAL)\n'
    '    target_sources(${TARGET_NAME} PRIVATE opencl-sphal.cpp opencl-sphal.h)\n'
    '    target_compile_definitions(${TARGET_NAME} PRIVATE GGML_OPENCL_USE_SPHAL)\n'
    '    target_link_libraries(${TARGET_NAME} PRIVATE ${CMAKE_DL_LIBS})\n'
    'else ()\n'
    '    target_link_libraries(${TARGET_NAME} PRIVATE ${OpenCL_LIBRARIES})\n'
    'endif ()',
    1
)
open(p_clcm, "w", encoding="utf-8").write(s_clcm)

p_pc = "ggml/src/ggml-opencl/cl-program-cache.cpp"
s_pc = open(p_pc, "r", encoding="utf-8").read()
s_pc = s_pc.replace(
    '#include "cl-program-cache.h"\n',
    '#include "cl-program-cache.h"\n#ifdef GGML_OPENCL_USE_SPHAL\n#include "opencl-sphal.h"\n#endif\n',
    1
)
open(p_pc, "w", encoding="utf-8").write(s_pc)

p_cl = "ggml/src/ggml-opencl/ggml-opencl.cpp"
s_cl = open(p_cl, "r", encoding="utf-8").read()
s_cl = s_cl.replace(
    '#include <CL/cl.h>\n',
    '#include <CL/cl.h>\n#ifdef GGML_OPENCL_USE_SPHAL\n#include "opencl-sphal.h"\n#endif\n',
    1
)
probe_anchor = "    cl_platform_id platform_ids[NPLAT];\n"
probe_inject = (
    "#ifdef GGML_OPENCL_USE_SPHAL\n"
    "    if (!ggml_opencl_sphal_init()) {\n"
    "        return found_devices;\n"
    "    }\n"
    "#endif\n"
    + probe_anchor
)
assert probe_anchor in s_cl
s_cl = s_cl.replace(probe_anchor, probe_inject, 1)

old_xmem1 = """        cl_program prog =
            build_program_from_source(backend_ctx, kernel_src.c_str(), compile_opts);

        CL_CHECK((backend_ctx->kernel_adreno_xmem_pack_src_f32 =
            clCreateKernel(prog, "adreno_xmem_pack_src_f32", &err), err));
        CL_CHECK((backend_ctx->kernel_adreno_xmem_prepack_weight_f16 =
            clCreateKernel(prog, "adreno_xmem_prepack_weight_f16", &err), err));
        CL_CHECK((backend_ctx->kernel_gemm_xmem_f16_f32_os8 =
            clCreateKernel(prog, "kernel_gemm_xmem_f16_f32_os8", &err), err));
        CL_CHECK((backend_ctx->kernel_adreno_xmem_store_dst_f32 =
            clCreateKernel(prog, "adreno_xmem_store_dst_f32", &err), err));
        CL_CHECK(clReleaseProgram(prog));"""

new_xmem1 = """        cl_program prog = build_program_from_source_ex(
            backend_ctx->context, backend_ctx->device, kernel_src.c_str(), compile_opts,
            false, "gemm_xmem_f16_f32_os8", backend_ctx->queue);
        if (prog) {
            CL_CHECK((backend_ctx->kernel_adreno_xmem_pack_src_f32 =
                clCreateKernel(prog, "adreno_xmem_pack_src_f32", &err), err));
            CL_CHECK((backend_ctx->kernel_adreno_xmem_prepack_weight_f16 =
                clCreateKernel(prog, "adreno_xmem_prepack_weight_f16", &err), err));
            CL_CHECK((backend_ctx->kernel_gemm_xmem_f16_f32_os8 =
                clCreateKernel(prog, "kernel_gemm_xmem_f16_f32_os8", &err), err));
            CL_CHECK((backend_ctx->kernel_adreno_xmem_store_dst_f32 =
                clCreateKernel(prog, "adreno_xmem_store_dst_f32", &err), err));
            CL_CHECK(clReleaseProgram(prog));
        } else {
            backend_ctx->adreno_xmem_gemm_enabled = false;
        }"""
assert old_xmem1 in s_cl
s_cl = s_cl.replace(old_xmem1, new_xmem1, 1)

old_xmem2 = """        cl_program program = build_program_from_source(backend_ctx, kernel_src.c_str(), compile_opts);

        auto & xmem_attn = backend_ctx->adreno_xmem_attn;"""
new_xmem2 = """        cl_program program = build_program_from_source_ex(
            backend_ctx->context, backend_ctx->device, kernel_src.c_str(), compile_opts,
            false, "sdpa_xmem_f32_f16_os8", backend_ctx->queue);
        if (program) {
        auto & xmem_attn = backend_ctx->adreno_xmem_attn;"""
assert old_xmem2 in s_cl
s_cl = s_cl.replace(old_xmem2, new_xmem2, 1)
s_cl = s_cl.replace(
    "        xmem_attn.compiled = true;\n        GGML_LOG_CONT(\".\");\n    }\n#endif // GGML_OPENCL_USE_ADRENO_KERNELS",
    "        xmem_attn.compiled = true;\n        GGML_LOG_CONT(\".\");\n        }\n    }\n#endif // GGML_OPENCL_USE_ADRENO_KERNELS",
    1
)
open(p_cl, "w", encoding="utf-8").write(s_cl)
PY
      touch .poco_adreno840_v2_patched
    )
    # Limpiar el binario antiguo vulkan-shaders-gen para que se recompile con N=2u y fix .d
    if [ -d "$BUILD_DIR" ]; then
      find "$BUILD_DIR" -name "*vulkan-shaders-gen*" -exec rm -rf {} + 2>/dev/null || true
    fi
    ok "Parches v2 en llama.cpp aplicados (Vulkan N=2u + depfiles .d + OpenCL SPHAL)."
  else
    ok "Parches v2 en llama.cpp ya estaban aplicados."
  fi

  # Parches Go v2 en Ollama 0.40.16 (admisión iGPU Android + soporte dual Vulkan y OpenCL + VRAM GPUOpenCL)
  if [ ! -f "$OLLAMA_SRC/.poco_go_v2_patched" ]; then
    info "Aplicando parches Go v2 en Ollama (admisión iGPU Android + soporte Vulkan/OpenCL)..."
    (
      cd "$OLLAMA_SRC"
      git checkout -- .
    )
    python3 - "$OLLAMA_SRC" <<'PY'
import os, sys
root = sys.argv[1]

# 1. ml/path.go: resolver ../lib/ollama en Android
p_path = os.path.join(root, "ml/path.go")
s = open(p_path, "r", encoding="utf-8").read()
s = s.replace('\t\tcase "linux":', '\t\tcase "linux", "android":', 1)
open(p_path, "w", encoding="utf-8").write(s)

# 2. ml/device.go: FlashAttention activo en Vulkan y OpenCL
p_dev = os.path.join(root, "ml/device.go")
s = open(p_dev, "r", encoding="utf-8").read()
s = s.replace('supportsFA := gpu.Library == "cpu" ||', 'supportsFA := false ||', 1)
s = s.replace('gpu.Library == "Vulkan"', 'gpu.Library == "Vulkan" ||\n\t\t\tgpu.Library == "OpenCL"', 1)
open(p_dev, "w", encoding="utf-8").write(s)

# 3. discover/runner.go: NO descartar GPUs integradas UMA (Adreno 840) en Android
p_run = os.path.join(root, "discover/runner.go")
s = open(p_run, "r", encoding="utf-8").read()
s = s.replace(
    'if runtime.GOOS == "darwin" && runtime.GOARCH == "arm64" {',
    'if (runtime.GOOS == "darwin" && runtime.GOARCH == "arm64") || runtime.GOOS == "android" {',
    1
)
open(p_run, "w", encoding="utf-8").write(s)

# 4. discover/llama_server.go: identificar Library="OpenCL" para GPUOpenCL
p_disc = os.path.join(root, "discover/llama_server.go")
s = open(p_disc, "r", encoding="utf-8").read()
old_inf = '\tcase strings.Contains(combined, "vulkan"):\n\t\treturn "Vulkan"'
new_inf = old_inf + '\n\tcase strings.Contains(combined, "opencl"):\n\t\treturn "OpenCL"'
s = s.replace(old_inf, new_inf, 1)
open(p_disc, "w", encoding="utf-8").write(s)

# 5. llm/llama_server.go: anteponer /system/lib64, limpiar VK_ICD_FILENAMES, y mapear buffer "OpenCL" -> "GPUOpenCL"
p_srv = os.path.join(root, "llm/llama_server.go")
s = open(p_srv, "r", encoding="utf-8").read()
target1 = '\tif libraryPath, ok := os.LookupEnv(llamaServerLibraryPathEnv()); ok {'
inject1 = '\tif runtime.GOOS == "android" {\n\t\taddPath("/system/lib64")\n\t}\n' + target1
s = s.replace(target1, inject1, 1)

target2 = '\tcmd.Env = os.Environ()'
inject2 = (
    '\tcmd.Env = os.Environ()\n'
    '\tif runtime.GOOS == "android" && os.Getenv("OLLAMA_VK_KEEP_ICD") == "" {\n'
    '\t\tfiltered := cmd.Env[:0]\n'
    '\t\tfor _, kv := range cmd.Env {\n'
    '\t\t\tif !strings.HasPrefix(kv, "VK_ICD_FILENAMES=") && !strings.HasPrefix(kv, "VK_DRIVER_FILES=") {\n'
    '\t\t\t\tfiltered = append(filtered, kv)\n'
    '\t\t\t}\n'
    '\t\t}\n'
    '\t\tcmd.Env = filtered\n'
    '\t}'
)
s = s.replace(target2, inject2, 1)

target3 = 'func deviceName(backendName string) string {\n'
inject3 = target3 + '\tif backendName == "OpenCL" {\n\t\treturn "GPUOpenCL"\n\t}\n'
s = s.replace(target3, inject3, 1)
open(p_srv, "w", encoding="utf-8").write(s)
PY
    touch "$OLLAMA_SRC/.poco_go_v2_patched"
    rm -f "$EXP_DIR/bin/ollama"
    ok "Fuentes Go v2 de Ollama adaptadas (Vulkan + OpenCL + iGPU Android)."
  fi

  # ------------------------- 4. FASE 4: Compilación Segura Anti-Signal-9 ------
  [ "${RECOMPILAR}" -eq 1 ] && rm -rf "$BUILD_DIR" "$EXP_DIR/bin/ollama" \
    "$EXP_DIR/lib/ollama/vulkan/libggml-vulkan.so" "$EXP_DIR/lib/ollama/opencl/libggml-opencl.so"

  # Detener temporalmente cualquier ollama serve en segundo plano para liberar RAM y slots de procesos
  pkill -f "ollama serve" 2>/dev/null || true

  NEED_CMAKE_BUILD=0
  [ ! -x "$EXP_DIR/lib/ollama/llama-server" ] && NEED_CMAKE_BUILD=1
  [ ! -f "$EXP_DIR/lib/ollama/vulkan/libggml-vulkan.so" ] && NEED_CMAKE_BUILD=1
  if [ "${ENABLE_OPENCL_BUILD}" -eq 1 ] && [ ! -f "$EXP_DIR/lib/ollama/opencl/libggml-opencl.so" ]; then
    NEED_CMAKE_BUILD=1
  fi

  if [ "${NEED_CMAKE_BUILD}" -eq 1 ]; then
    info "FASE 4/5 — Configurando y compilando backends GPU con concurrencia controlada (-j2, concurrencia reducida)..."
    export ASAN_OPTIONS="detect_leaks=0"
    SPIRV_CMAKE_DIR="$PREFIX/share/cmake/SPIRV-Headers"
    [ -d "$SPIRV_CMAKE_DIR" ] || SPIRV_CMAKE_DIR="$PREFIX/lib/cmake/SPIRV-Headers"

    OPENCL_CMAKE_ARGS=(-DGGML_OPENCL=OFF)
    if [ "${ENABLE_OPENCL_BUILD}" -eq 1 ]; then
      OPENCL_CMAKE_ARGS=(
        -DGGML_OPENCL=ON
        -DGGML_OPENCL_USE_SPHAL=ON
        -DGGML_OPENCL_EMBED_KERNELS=ON
        -DGGML_OPENCL_USE_ADRENO_KERNELS=ON
        -DGGML_OPENCL_TARGET_VERSION=300
        -DOpenCL_INCLUDE_DIRS="$PREFIX/include"
      )
    fi

    cmake -G Ninja \
      -S "$OLLAMA_SRC/llama/server" \
      -B "$BUILD_DIR" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$EXP_DIR" \
      -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ \
      -DCMAKE_C_FLAGS="-O3 -D_GNU_SOURCE -DSUBPROCESS_SPAWN_VIA_FORK=1" \
      -DCMAKE_CXX_FLAGS="-O3 -D_GNU_SOURCE -DSUBPROCESS_SPAWN_VIA_FORK=1" \
      -DCMAKE_SHARED_LINKER_FLAGS="-landroid-spawn" \
      -DCMAKE_EXE_LINKER_FLAGS="-landroid-spawn" \
      -DCMAKE_PREFIX_PATH="$PREFIX" \
      -DSPIRV-Headers_DIR="$SPIRV_CMAKE_DIR" \
      -DFETCHCONTENT_SOURCE_DIR_LLAMA_CPP="$LLAMA_SRC" \
      -DOLLAMA_LLAMA_CPP_SKIP_COMPAT_PATCH=ON \
      -DBUILD_SHARED_LIBS=ON \
      -DLLAMA_CURL=OFF \
      -DLLAMA_BUILD_TESTS=OFF \
      -DGGML_LLAMAFILE=OFF \
      -DGGML_BACKEND_DL=ON \
      -DGGML_NATIVE=OFF \
      -DGGML_CPU_ALL_VARIANTS=OFF \
      -DGGML_CPU_ARM_ARCH="armv8.2-a+dotprod+i8mm+fp16" \
      -DGGML_OPENMP=OFF \
      -DGGML_VULKAN=ON \
      -DVulkan_LIBRARY="/system/lib64/libvulkan.so" \
      -DVulkan_INCLUDE_DIR="$PREFIX/include" \
      -DVulkan_GLSLC_EXECUTABLE="$PREFIX/bin/glslc" \
      "${OPENCL_CMAKE_ARGS[@]}"

    # Paso 4A: Compilar primero llama-server + ggml-cpu + ggml-opencl (0 subprocesos glslc, ~45 seg)
    if [ "${ENABLE_OPENCL_BUILD}" -eq 1 ]; then
      info "4A) Compilando llama-server + libggml-opencl.so (Qualcomm Adreno OpenCL 3.0)..."
      cmake --build "$BUILD_DIR" --target llama-server ggml-cpu ggml-opencl -j2
    else
      info "4A) Compilando llama-server + ggml-cpu..."
      cmake --build "$BUILD_DIR" --target llama-server ggml-cpu -j2
    fi

    # Paso 4B: Compilar libggml-vulkan.so con -j2 y N=2u (máx. 4 glslc simultáneos -> mitigacion de signal 9)
    info "4B) Compilando libggml-vulkan.so (reanudando incrementalmente con -j2 anti-signal-9)..."
    cmake --build "$BUILD_DIR" --target ggml-vulkan -j2

    cmake --install "$BUILD_DIR" --prefix "$EXP_DIR" --component llama-server

    mkdir -p "$EXP_DIR/lib/ollama/vulkan" "$EXP_DIR/lib/ollama/opencl"
    find "$BUILD_DIR" -name "libggml-vulkan.so*" -exec cp -af {} "$EXP_DIR/lib/ollama/vulkan/" \;
    if [ "${ENABLE_OPENCL_BUILD}" -eq 1 ]; then
      find "$BUILD_DIR" -name "libggml-opencl.so*" -exec cp -af {} "$EXP_DIR/lib/ollama/opencl/" \;
    fi
    rm -f "$EXP_DIR/lib/ollama/libggml-vulkan.so"* "$EXP_DIR/lib/ollama/libggml-opencl.so"* 2>/dev/null || true

    ok "Backends nativos instalados en $EXP_DIR/lib/ollama/{vulkan,opencl}/."
  else
    ok "llama-server y backends GPU ya estaban compilados en $EXP_DIR (omitido)."
  fi

  # Enlaces locales en $ORIGIN hacia /system/lib64/libvulkan.so (sin tocar $PREFIX/lib)
  ln -sf "/system/lib64/libvulkan.so" "$EXP_DIR/lib/ollama/vulkan/libvulkan.so"
  ln -sf "/system/lib64/libvulkan.so" "$EXP_DIR/lib/ollama/vulkan/libvulkan.so.1"
  ln -sf "/system/lib64/libvulkan.so" "$EXP_DIR/lib/ollama/libvulkan.so"
  ln -sf "/system/lib64/libvulkan.so" "$EXP_DIR/lib/ollama/libvulkan.so.1"

  if [ ! -x "$EXP_DIR/bin/ollama" ]; then
    info "4C) Compilando binario Go experimental $EXP_DIR/bin/ollama (GOMAXPROCS=2 -p 2)..."
    (
      cd "$OLLAMA_SRC"
      export CGO_ENABLED=1
      export GOMAXPROCS=2
      export CC=clang
      export CXX=clang++
      export CGO_CFLAGS="-O2"
      export CGO_LDFLAGS="-landroid-spawn"
      go build -p 2 -trimpath \
        -ldflags="-w -s -X=github.com/ollama/ollama/version.Version=0.40.16-adreno840-gpu -X=github.com/ollama/ollama/server.mode=release" \
        -o "$EXP_DIR/bin/ollama" .
    )
    ok "Binario Go experimental compilado: $($EXP_DIR/bin/ollama --version 2>/dev/null || true)"
  else
    ok "Binario Go experimental $EXP_DIR/bin/ollama ya compilado."
  fi
fi

[ -x "$EXP_DIR/bin/ollama" ] || die "No existe $EXP_DIR/bin/ollama."
[ -f "$EXP_DIR/lib/ollama/vulkan/libggml-vulkan.so" ] || die "No existe libggml-vulkan.so."

# --------------------------- Wrappers aislados Vulkan y OpenCL ----------------
cat > "$EXP_DIR/bin/ollama-adreno-vulkan-serve" <<EOF
#!$PREFIX/bin/bash
set -euo pipefail
termux-wake-lock 2>/dev/null || true
unset VK_ICD_FILENAMES VK_DRIVER_FILES
export LD_LIBRARY_PATH="/system/lib64:$EXP_DIR/lib/ollama/vulkan:$EXP_DIR/lib/ollama:$PREFIX/lib"
export OLLAMA_MODELS="\${OLLAMA_MODELS:-\$HOME/.ollama/models}"
export OLLAMA_VULKAN="1"
export OLLAMA_IGPU_ENABLE="1"
export OLLAMA_LLM_LIBRARY="vulkan"
export OLLAMA_FLASH_ATTENTION="1"
export OLLAMA_KV_CACHE_TYPE="q8_0"
export OLLAMA_CONTEXT_LENGTH="${CTX_TARGET}"
export OLLAMA_NUM_THREADS="6"
export OLLAMA_KEEP_ALIVE="20m"
export OLLAMA_HOST="\${OLLAMA_HOST:-127.0.0.1:${EXP_PORT}}"
exec "$EXP_DIR/bin/ollama" serve
EOF
chmod +x "$EXP_DIR/bin/ollama-adreno-vulkan-serve"

cat > "$EXP_DIR/bin/ollama-adreno-opencl-serve" <<EOF
#!$PREFIX/bin/bash
set -euo pipefail
termux-wake-lock 2>/dev/null || true
unset VK_ICD_FILENAMES VK_DRIVER_FILES
export TMPDIR="$CL_CACHE_DIR"
export LD_LIBRARY_PATH="/system/lib64:$EXP_DIR/lib/adreno-opencl:$EXP_DIR/lib/ollama/opencl:$EXP_DIR/lib/ollama:$PREFIX/lib"
export GGML_OPENCL_LOADER_PATH="${OPENCL_LOADER_OVERRIDE}"
export OLLAMA_MODELS="\${OLLAMA_MODELS:-\$HOME/.ollama/models}"
export OLLAMA_IGPU_ENABLE="1"
export OLLAMA_LLM_LIBRARY="opencl"
export OLLAMA_FLASH_ATTENTION="1"
export OLLAMA_KV_CACHE_TYPE="q8_0"
export OLLAMA_CONTEXT_LENGTH="${CTX_TARGET}"
export OLLAMA_NUM_THREADS="6"
export OLLAMA_KEEP_ALIVE="20m"
export OLLAMA_HOST="\${OLLAMA_HOST:-127.0.0.1:${EXP_PORT}}"
exec "$EXP_DIR/bin/ollama" serve
EOF
chmod +x "$EXP_DIR/bin/ollama-adreno-opencl-serve"

cat > "$EXP_DIR/bin/ollama-adreno-serve" <<EOF
#!$PREFIX/bin/bash
set -euo pipefail
MODE="\${1:-}"
if [ -z "\$MODE" ] && [ -f "$EXP_DIR/best_backend.txt" ]; then
  MODE="--\$(cat "$EXP_DIR/best_backend.txt")"
fi
case "\$MODE" in
  --opencl) exec "$EXP_DIR/bin/ollama-adreno-opencl-serve" ;;
  *)        exec "$EXP_DIR/bin/ollama-adreno-vulkan-serve" ;;
esac
EOF
chmod +x "$EXP_DIR/bin/ollama-adreno-serve"

cat > "$EXP_DIR/bin/conectar-poco-agent-gpu" <<EOF
#!$PREFIX/bin/bash
set -euo pipefail
BACKEND_ARG="\${1:-}"
if [ -f "$PREFIX/bin/poco-agent" ] && [ ! -f "$EXP_DIR/poco-agent.cpu.bak" ]; then
  cp -a "$PREFIX/bin/poco-agent" "$EXP_DIR/poco-agent.cpu.bak"
fi
pkill -f "ollama serve" 2>/dev/null || true
sleep 1
OLLAMA_HOST="127.0.0.1:11434" nohup "$EXP_DIR/bin/ollama-adreno-serve" \$BACKEND_ARG > "\$HOME/.ollama-adreno-serve.log" 2>&1 &
echo "[✓] Ollama Experimental Adreno 840 activo en 127.0.0.1:11434 (poco-agent conectado a GPU)."
echo "    • Forzar Vulkan : $EXP_DIR/bin/conectar-poco-agent-gpu --vulkan"
echo "    • Forzar OpenCL : $EXP_DIR/bin/conectar-poco-agent-gpu --opencl"
echo "    • Volver a CPU  : $EXP_DIR/bin/restaurar-poco-agent-cpu"
EOF
chmod +x "$EXP_DIR/bin/conectar-poco-agent-gpu"

cat > "$EXP_DIR/bin/restaurar-poco-agent-cpu" <<EOF
#!$PREFIX/bin/bash
set -euo pipefail
pkill -f "$EXP_DIR/bin/ollama" 2>/dev/null || true
if [ -f "$EXP_DIR/poco-agent.cpu.bak" ]; then
  cp -a "$EXP_DIR/poco-agent.cpu.bak" "$PREFIX/bin/poco-agent"
fi
echo "[✓] Motor experimental detenido; tu Ollama CPU original sigue 100% intacto."
EOF
chmod +x "$EXP_DIR/bin/restaurar-poco-agent-cpu"

# --------------------------- 5. FASE 5: Auditoría Triple (CPU vs Vulkan vs OpenCL)
cat > "$EXP_DIR/bin/probar-adreno-real" <<'VERIFY_EOF'
#!/data/data/com.termux/files/usr/bin/python3
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
import urllib.request
import urllib.error

EXP_DIR = os.path.expanduser("~/ollama-vulkan-exp")
PREFIX = os.environ.get("PREFIX", "/data/data/com.termux/files/usr")
LOG_DIR = os.path.join(EXP_DIR, "logs")
CL_CACHE_DIR = os.path.join(EXP_DIR, "cl-cache")
os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(CL_CACHE_DIR, exist_ok=True)

MODEL = os.environ.get("MODEL_TARGET", "huihui_ai/qwen3.5-abliterated:2B")
CTX = int(os.environ.get("CTX_TARGET", "73728"))
OPENCL_OVERRIDE = os.environ.get("OPENCL_LOADER_OVERRIDE", "")
PROMPT = (
    "Explica en espanol con precision tecnica como funciona una cola de "
    "computo GPU sobre memoria unificada LPDDR5X en cinco puntos numerados."
)

report_lines = []
def log(msg=""):
    print(msg, flush=True)
    report_lines.append(msg)

def read_first_line(path):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except Exception:
        return None

def sample_kgsl_busy():
    raw = read_first_line("/sys/class/kgsl/kgsl-3d0/gpubusy")
    if raw:
        parts = raw.split()
        if len(parts) >= 2:
            try:
                return int(parts[0]), int(parts[1])
            except ValueError:
                pass
    pct = read_first_line("/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage")
    if pct is not None:
        m = re.search(r"(\d+)", pct)
        if m:
            return int(m.group(1)), 100
    return None

def read_proc_cpu_ticks(pid):
    try:
        st = open(f"/proc/{pid}/stat", "r").read()
        rparen = st.rfind(")")
        fields = st[rparen+2:].split()
        return int(fields[11]) + int(fields[12])
    except Exception:
        return None

def find_runner_pids(marker_substr):
    pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            cmd = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\x00", b" ").decode("utf-8", "replace")
            if "llama-server" in cmd and marker_substr in cmd:
                pids.append(int(entry))
        except Exception:
            pass
    return pids

def inspect_runner_kernel_evidence(pid):
    evidence = {"maps_gpu": [], "fds_kgsl": [], "fdinfo_kgsl": []}
    try:
        seen = set()
        for line in open(f"/proc/{pid}/maps", "r", errors="replace"):
            if "/" in line:
                path = "/" + line.split("/", 1)[1].strip()
                if any(k in path.lower() for k in ("vulkan", "adreno", "opencl", "libcb", "libgsl", "ggml")) and path not in seen:
                    seen.add(path)
                    evidence["maps_gpu"].append(path)
    except Exception:
        pass

    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
                if "kgsl" in target or "dri" in target:
                    evidence["fds_kgsl"].append(f"fd/{fd} -> {target}")
                    try:
                        fdi = open(f"/proc/{pid}/fdinfo/{fd}", "r", errors="replace").read().strip()
                        if fdi:
                            evidence["fdinfo_kgsl"].append(f"fdinfo/{fd}: " + " | ".join(fdi.splitlines()[:3]))
                    except Exception:
                        pass
            except Exception:
                pass
    except Exception:
        pass
    return evidence

def wait_http(port, timeout=30):
    url = f"http://127.0.0.1:{port}/api/version"
    t0 = time.time()
    while time.time() - t0 < timeout:
        try:
            with urllib.request.urlopen(url, timeout=2) as r:
                return json.loads(r.read().decode())
        except Exception:
            time.sleep(0.5)
    raise RuntimeError(f"Servidor en puerto {port} no respondio")

def benchmark_backend(label, ollama_bin, runner_marker, port, extra_env, log_filename):
    log_path = os.path.join(LOG_DIR, log_filename)
    env = os.environ.copy()
    env.pop("VK_ICD_FILENAMES", None)
    env.pop("VK_DRIVER_FILES", None)
    env.update({
        "OLLAMA_MODELS": os.path.expanduser(os.environ.get("OLLAMA_MODELS", "~/.ollama/models")),
        "OLLAMA_FLASH_ATTENTION": "1",
        "OLLAMA_KV_CACHE_TYPE": "q8_0",
        "OLLAMA_CONTEXT_LENGTH": str(CTX),
        "OLLAMA_NUM_THREADS": "6",
        "OLLAMA_HOST": f"127.0.0.1:{port}",
    })
    env.update(extra_env)

    lf = open(log_path, "w")
    proc = subprocess.Popen([ollama_bin, "serve"], env=env, stdout=lf, stderr=subprocess.STDOUT, preexec_fn=os.setsid)
    try:
        wait_http(port, 30)
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/tags", timeout=10) as response:
            names = [m.get("name", "") for m in json.load(response).get("models", [])]
        expected = MODEL if ":" in MODEL.rsplit("/", 1)[-1] else MODEL + ":latest"
        if MODEL not in names and expected not in names:
            raise RuntimeError(f"Modelo {MODEL!r} no registrado en {env['OLLAMA_MODELS']}. Disponibles: {names}. Usa scripts/import-gguf.sh.")
        # Warmup (carga pesos + compila kernels OpenCL la primera vez)
        warm_req = urllib.request.Request(
            f"http://127.0.0.1:{port}/api/generate",
            data=json.dumps({
                "model": MODEL,
                "prompt": "Hola",
                "stream": False,
                "keep_alive": "10m",
                "options": {"num_ctx": CTX, "num_predict": 2, "temperature": 0, "seed": 42, "num_batch": 256}
            }).encode(),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(warm_req, timeout=420) as r:
            json.loads(r.read().decode())

        ps_out = subprocess.check_output([ollama_bin, "ps"], env=env, text=True).strip()
        time.sleep(1.0)
        pids = find_runner_pids(runner_marker)
        runner_pid = pids[0] if pids else None

        idle_b0 = sample_kgsl_busy()
        time.sleep(0.5)
        idle_b1 = sample_kgsl_busy()
        idle_gpu = None
        if idle_b0 and idle_b1 and idle_b1[1] > idle_b0[1] and idle_b0[1] != 100:
            idle_gpu = 100.0 * (idle_b1[0] - idle_b0[0]) / max(1, (idle_b1[1] - idle_b0[1]))
        elif idle_b1 and idle_b1[1] == 100:
            idle_gpu = float(idle_b1[0])

        holder = {}
        def worker():
            req = urllib.request.Request(
                f"http://127.0.0.1:{port}/api/generate",
                data=json.dumps({
                    "model": MODEL,
                    "prompt": PROMPT,
                    "stream": False,
                    "keep_alive": "5m",
                    "options": {"num_ctx": CTX, "num_predict": 128, "temperature": 0, "seed": 42, "num_batch": 256}
                }).encode(),
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=600) as resp:
                holder["data"] = json.loads(resp.read().decode())

        clk_tck = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
        th = threading.Thread(target=worker, daemon=True)
        cpu_t0 = read_proc_cpu_ticks(runner_pid) if runner_pid else None
        wall_t0 = time.time()
        kgsl_0 = sample_kgsl_busy()
        th.start()

        kernel_ev = {}
        pct_samples = []
        while th.is_alive():
            if not runner_pid:
                pids = find_runner_pids(runner_marker)
                if pids:
                    runner_pid = pids[0]
                    cpu_t0 = read_proc_cpu_ticks(runner_pid)
                    wall_t0 = time.time()
            if runner_pid and not kernel_ev.get("fds_kgsl"):
                kernel_ev = inspect_runner_kernel_evidence(runner_pid)
            b = sample_kgsl_busy()
            if b and b[1] == 100:
                pct_samples.append(float(b[0]))
            time.sleep(0.12)

        th.join()
        if "data" not in holder:
            raise RuntimeError(f"Inferencia en {label} fallo; revisar {log_path}")

        wall_dt = max(0.001, time.time() - wall_t0)
        cpu_t1 = read_proc_cpu_ticks(runner_pid) if runner_pid else None
        kgsl_1 = sample_kgsl_busy()

        cpu_pct = None
        if cpu_t0 is not None and cpu_t1 is not None and cpu_t1 >= cpu_t0:
            cpu_pct = 100.0 * ((cpu_t1 - cpu_t0) / clk_tck) / wall_dt

        active_gpu = None
        if kgsl_0 and kgsl_1 and kgsl_1[1] > kgsl_0[1] and kgsl_0[1] != 100:
            active_gpu = 100.0 * (kgsl_1[0] - kgsl_0[0]) / max(1, (kgsl_1[1] - kgsl_0[1]))
        elif pct_samples:
            active_gpu = sum(pct_samples) / len(pct_samples)

        if runner_pid and not kernel_ev:
            kernel_ev = inspect_runner_kernel_evidence(runner_pid)

        lf.flush()
        ggml_lines = []
        for l in open(log_path, "r", errors="replace"):
            if any(k in l for k in ("Adreno", "Vulkan", "OpenCL", "GPUOpenCL", "offloaded", "buffer size", "sphal")):
                if len(ggml_lines) < 18:
                    ggml_lines.append(l.strip())

        # Descargar modelo antes de cerrar
        try:
            urllib.request.urlopen(urllib.request.Request(
                f"http://127.0.0.1:{port}/api/generate",
                data=json.dumps({"model": MODEL, "keep_alive": 0}).encode(),
                headers={"Content-Type": "application/json"}
            ), timeout=20).read()
        except Exception:
            pass

        d = holder["data"]
        pe_tps = d.get("prompt_eval_count", 0) / max(1e-6, d.get("prompt_eval_duration", 1) / 1e9)
        ev_tps = d.get("eval_count", 0) / max(1e-6, d.get("eval_duration", 1) / 1e9)
        return {
            "ok": True,
            "label": label,
            "pid": runner_pid,
            "ps": ps_out,
            "cpu_pct": cpu_pct,
            "idle_gpu": idle_gpu,
            "active_gpu": active_gpu,
            "prefill_tps": pe_tps,
            "decode_tps": ev_tps,
            "response": d.get("response", "").strip()[:260],
            "kernel": kernel_ev,
            "ggml_lines": ggml_lines,
        }
    finally:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except Exception:
            pass
        lf.close()
        time.sleep(1.2)

log("==========================================================================")
log("  AUDITORIA HARDWARE GPU ADRENO 840 — VULKAN + OPENCL + CPU (CTX=73728)")
log("==========================================================================")
log(f"Modelo auditado : {MODEL} (cuantizacion: consultar metadatos del modelo)")
log(f"Contexto (ctx)  : {CTX} tokens (intacto)")
log("")

results = []

# 1. Probar Vulkan Adreno 840
log("[1/3] Auditando Backend VULKAN Nativo (Adreno 840 -> /dev/kgsl-3d0)...")
try:
    vk_res = benchmark_backend(
        "GPU Vulkan",
        f"{EXP_DIR}/bin/ollama",
        EXP_DIR,
        11435,
        {
            "LD_LIBRARY_PATH": f"/system/lib64:{EXP_DIR}/lib/ollama/vulkan:{EXP_DIR}/lib/ollama:{PREFIX}/lib",
            "OLLAMA_VULKAN": "1",
            "OLLAMA_IGPU_ENABLE": "1",
            "OLLAMA_LLM_LIBRARY": "vulkan",
            "OLLAMA_DEBUG": "1",
        },
        "audit-vulkan.log",
    )
    results.append(("vulkan", vk_res))
except Exception as e:
    log(f"  [!] Vulkan reporto error: {e}")
    if isinstance(e, urllib.error.HTTPError):
        log(e.read().decode("utf-8", "replace"))

# 2. Probar OpenCL Adreno 840 (si libggml-opencl.so fue compilado)
opencl_so = f"{EXP_DIR}/lib/ollama/opencl/libggml-opencl.so"
if os.path.isfile(opencl_so):
    log("\n[2/3] Auditando Backend OPENCL SPHAL Nativo (Adreno 840 -> /vendor/lib64/libOpenCL.so)...")
    log("      (Nota: la primera carga compila y guarda en cache los kernels .clbin para Adreno 840)")
    try:
        cl_env = {
            "TMPDIR": CL_CACHE_DIR,
            "LD_LIBRARY_PATH": f"/system/lib64:{EXP_DIR}/lib/adreno-opencl:{EXP_DIR}/lib/ollama/opencl:{EXP_DIR}/lib/ollama:{PREFIX}/lib",
            "OLLAMA_IGPU_ENABLE": "1",
            "OLLAMA_LLM_LIBRARY": "opencl",
            "OLLAMA_DEBUG": "1",
        }
        if OPENCL_OVERRIDE:
            cl_env["GGML_OPENCL_LOADER_PATH"] = OPENCL_OVERRIDE
        cl_res = benchmark_backend("GPU OpenCL", f"{EXP_DIR}/bin/ollama", EXP_DIR, 11437, cl_env, "audit-opencl.log")
        results.append(("opencl", cl_res))
    except Exception as e:
        log(f"  [!] OpenCL reporto error: {e}")
        if isinstance(e, urllib.error.HTTPError):
            log(e.read().decode("utf-8", "replace"))

# 3. Probar Ollama CPU Original ($PREFIX/bin/ollama) para comparación A/B
orig_bin = os.path.join(PREFIX, "bin/ollama")
cpu_res = None
if os.path.isfile(orig_bin):
    log("\n[3/3] Auditando tu Ollama CPU Original ($PREFIX/bin/ollama) para comparativa A/B...")
    try:
        cpu_res = benchmark_backend("CPU Original", orig_bin, PREFIX, 11436, {}, "audit-cpu.log")
    except Exception as e:
        log(f"  [!] CPU original reporto error: {e}")

if not os.path.isfile(orig_bin):
    log("  [i] CPU original no encontrado; no se afirma comparacion GPU vs CPU.")

for key, r in results:
    log(f"\n--- Detalle de Evidencia Física: {r['label']} (PID runner {r['pid']}) ---")
    log("  ollama ps:")
    for l in r["ps"].splitlines():
        log("    " + l)
    log("  Descriptores /proc/<PID>/fd abiertos en el kernel:")
    for fd in r["kernel"].get("fds_kgsl", []):
        log("    • " + fd)
    log("  Librerías GPU mapeadas en /proc/<PID>/maps:")
    for m in r["kernel"].get("maps_gpu", []):
        log("    • " + m)
    log("  Trazas GGML de capas y buffers en GPU:")
    for gl in r["ggml_lines"][:12]:
        log("    " + gl)

def fmt_pct(v):
    return f"{v:.1f}%" if v is not None else "n/d (SELinux)"

log("\n==========================================================================")
log(f"  TABLA COMPARATIVA FINAL ({MODEL} | ctx={CTX})")
log("==========================================================================")
log(f"  {'Motor':<15} | {'/dev/kgsl-3d0':<14} | {'%CPU Runner':<13} | {'GPU Busy':<14} | {'Prefill':<12} | {'Decode'}")
log("  " + "-" * 86)
all_rows = ([cpu_res] if cpu_res else []) + [r for _, r in results]
for r in all_rows:
    kg = f"{len(r['kernel'].get('fds_kgsl', []))} FDs"
    gb = fmt_pct(r["active_gpu"])
    log(f"  {r['label']:<15} | {kg:<14} | {fmt_pct(r['cpu_pct']):<13} | {gb:<14} | {r['prefill_tps']:>6.2f} tok/s | {r['decode_tps']:>6.2f} tok/s")

verified_gpu = []
for key, r in results:
    has_gpu_ps = ("gpu" in r["ps"].lower()) and ("100% cpu" not in r["ps"].lower())
    has_kgsl = len(r["kernel"].get("fds_kgsl", [])) > 0
    no_lvp = not any("lvp" in m.lower() or "llvmpipe" in m.lower() for m in r["kernel"].get("maps_gpu", []))
    if has_gpu_ps and has_kgsl and no_lvp:
        verified_gpu.append((key, r))

log("\n==========================================================================")
if verified_gpu:
    # Seleccionar automáticamente el backend GPU con mejor velocidad de decode
    best_key, best_r = max(verified_gpu, key=lambda x: x[1]["decode_tps"])
    open(os.path.join(EXP_DIR, "best_backend.txt"), "w").write(best_key)
    log(f"  VEREDICTO FINAL: EXITO DEMOSTRADO EN HARDWARE REAL ADRENO 840")
    log(f"  • Backends GPU reales verificados : {', '.join(x[1]['label'] for x in verified_gpu)}")
    log(f"  • Backend optimo preseleccionado  : {best_r['label']} ({best_r['decode_tps']:.2f} tok/s decode, {best_r['prefill_tps']:.2f} tok/s prefill)")
    log("  • Muestra generada (no verifica por si sola exactitud numerica ni cuantizacion):")
    for l in best_r["response"].splitlines()[:5]:
        log("      " + l)
    exit_code = 0
else:
    log("  VEREDICTO FINAL: INCOMPLETO — REVISAR LOGS EN ~/ollama-vulkan-exp/logs/")
    exit_code = 2
log("==========================================================================")

out_txt = "\n".join(report_lines) + "\n"
open(os.path.join(EXP_DIR, "evidencia-adreno840.txt"), "w", encoding="utf-8").write(out_txt)
dl_dir = os.path.expanduser("~/storage/downloads")
if os.path.isdir(dl_dir):
    try:
        open(os.path.join(dl_dir, "evidencia-adreno840.txt"), "w", encoding="utf-8").write(out_txt)
    except Exception:
        pass

sys.exit(exit_code)
VERIFY_EOF
chmod +x "$EXP_DIR/bin/probar-adreno-real"

if [ "$SKIP_AUDIT" -eq 1 ]; then
  ok "Compilacion terminada. Importa un GGUF y ejecuta scripts/benchmark.sh."
  exit 0
fi

info "FASE 5/5 — Ejecutando auditoría comparativa en vivo (Vulkan + OpenCL + CPU, ctx=${CTX_TARGET})..."
MODEL_TARGET="${MODEL_TARGET}" CTX_TARGET="${CTX_TARGET}" OPENCL_LOADER_OVERRIDE="${OPENCL_LOADER_OVERRIDE:-}" \
  "$EXP_DIR/bin/probar-adreno-real"

printf '\n%s\n' "${C_GREEN}${C_BOLD}══════════════════════════════════════════════════════════════════════${C_RESET}"
printf '%s\n'   "${C_GREEN}${C_BOLD}  Experimento Dual GPU (Vulkan + OpenCL) Completado: ~/ollama-vulkan-exp${C_RESET}"
printf '%s\n'   "${C_GREEN}${C_BOLD}══════════════════════════════════════════════════════════════════════${C_RESET}"
printf '  • Informe completo en : %s~/storage/downloads/evidencia-adreno840.txt%s\n' "${C_YELLOW}" "${C_RESET}"
printf '  • Conectar poco-agent (auto mejor GPU) : %s~/ollama-vulkan-exp/bin/conectar-poco-agent-gpu%s\n' "${C_CYAN}" "${C_RESET}"
printf '  • Conectar poco-agent forzando Vulkan  : %s~/ollama-vulkan-exp/bin/conectar-poco-agent-gpu --vulkan%s\n' "${C_CYAN}" "${C_RESET}"
printf '  • Conectar poco-agent forzando OpenCL  : %s~/ollama-vulkan-exp/bin/conectar-poco-agent-gpu --opencl%s\n' "${C_CYAN}" "${C_RESET}"
printf '  • Restaurar tu Ollama CPU original     : %s~/ollama-vulkan-exp/bin/restaurar-poco-agent-cpu%s\n\n' "${C_CYAN}" "${C_RESET}"
