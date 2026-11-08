/*
 * VK_LAYER_KNULLI_powervr_present
 *
 * Works around a defect in the PowerVR Rogue VK_KHR_display WSI on the
 * Allwinner A133 (libVK_IMG).  vkQueuePresentKHR returns at a vblank, but the
 * flip it queued only latches at the *next* one.  The surface caps allow at
 * most two images, so at every instant one image is on screen and the other is
 * the one about to go on screen -- there is never a free buffer.  The image
 * vkAcquireNextImageKHR hands back is live for the whole coming frame, so
 * anything the application renders into it is scanned out as it is written.
 *
 * Measured on a 1024x768 63Hz panel: acquire never blocks (0.00ms over
 * hundreds of frames) and a render held for N ms paints a stale band N/16.46
 * of the screen tall.  A one-frame-late flip needs three buffers to hide, and
 * three are not available, so the buffer cannot be made free.  Only the window
 * in which it is inconsistent can be made short.
 *
 * That is what this layer does.  The application is handed private "shadow"
 * images to render into and never touches a live buffer; at present time a
 * single full-screen copy moves the finished frame into the real swapchain
 * image.  The copy measures ~2.4ms, short enough to fall inside blanking in
 * practice -- verified indistinguishable from a swapchain that is only ever
 * flipped, never written.
 *
 * The layer is deliberately narrow: it only engages for swapchains it can
 * shadow, and passes everything else straight through.
 */

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>

/* Not defined by vk_layer.h; the loader only needs the symbols visible. */
#define VK_LAYER_EXPORT __attribute__((visibility("default")))

#define MAX_SWAPCHAIN_IMAGES 8

struct instance_data {
	VkInstance                              instance;
	PFN_vkGetInstanceProcAddr               gpa;
	PFN_vkDestroyInstance                   DestroyInstance;
	PFN_vkGetPhysicalDeviceMemoryProperties GetPhysicalDeviceMemoryProperties;
	struct instance_data                   *next;
};

struct swapchain_data {
	VkSwapchainKHR    swapchain;
	struct device_data *dd;
	uint32_t          count;
	VkImage           real[MAX_SWAPCHAIN_IMAGES];
	VkImage           shadow[MAX_SWAPCHAIN_IMAGES];
	VkDeviceMemory    memory[MAX_SWAPCHAIN_IMAGES];
	VkCommandBuffer   cmd[MAX_SWAPCHAIN_IMAGES];
	VkFence           copy_fence[MAX_SWAPCHAIN_IMAGES];
	/* Set once the app has been told about the shadow images.  Until then
	 * the swapchain is still a candidate for passthrough. */
	int               active;
	uint32_t          width;
	uint32_t          height;
	struct swapchain_data *next;
};

struct device_data {
	VkDevice          device;
	VkPhysicalDevice  gpu;
	struct instance_data *id;
	uint32_t          queue_family;
	VkCommandPool     pool;
	VkPhysicalDeviceMemoryProperties mem_props;

	PFN_vkGetDeviceProcAddr        gdpa;
	PFN_vkDestroyDevice            DestroyDevice;
	PFN_vkCreateSwapchainKHR       CreateSwapchainKHR;
	PFN_vkDestroySwapchainKHR      DestroySwapchainKHR;
	PFN_vkGetSwapchainImagesKHR    GetSwapchainImagesKHR;
	PFN_vkAcquireNextImageKHR      AcquireNextImageKHR;
	PFN_vkQueuePresentKHR          QueuePresentKHR;
	PFN_vkCreateImage              CreateImage;
	PFN_vkDestroyImage             DestroyImage;
	PFN_vkGetImageMemoryRequirements GetImageMemoryRequirements;
	PFN_vkAllocateMemory           AllocateMemory;
	PFN_vkFreeMemory               FreeMemory;
	PFN_vkBindImageMemory          BindImageMemory;
	PFN_vkCreateCommandPool        CreateCommandPool;
	PFN_vkDestroyCommandPool       DestroyCommandPool;
	PFN_vkAllocateCommandBuffers   AllocateCommandBuffers;
	PFN_vkBeginCommandBuffer       BeginCommandBuffer;
	PFN_vkEndCommandBuffer         EndCommandBuffer;
	PFN_vkCmdPipelineBarrier       CmdPipelineBarrier;
	PFN_vkCmdCopyImage             CmdCopyImage;
	PFN_vkCreateFence              CreateFence;
	PFN_vkDestroyFence             DestroyFence;
	PFN_vkWaitForFences            WaitForFences;
	PFN_vkResetFences              ResetFences;
	PFN_vkQueueSubmit              QueueSubmit;

	struct device_data *next;
};

/* A passthrough and a shadowed swapchain look identical from outside, so make
 * the layer say which one it picked. */
static int g_debug = -1;

static void dbg(const char *fmt, ...)
{
	va_list ap;
	if (g_debug < 0)
		g_debug = getenv("KNULLI_POWERVR_PRESENT_DEBUG") ? 1 : 0;
	if (!g_debug)
		return;
	fprintf(stderr, "[powervr-present] ");
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fputc('\n', stderr);
}

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static struct instance_data  *g_instances;
static struct device_data    *g_devices;
static struct swapchain_data *g_swapchains;

static struct instance_data *find_instance(VkInstance i)
{
	struct instance_data *d;
	for (d = g_instances; d; d = d->next)
		if (d->instance == i)
			return d;
	return NULL;
}

static struct device_data *find_device(VkDevice v)
{
	struct device_data *d;
	for (d = g_devices; d; d = d->next)
		if (d->device == v)
			return d;
	return NULL;
}

static struct swapchain_data *find_swapchain(VkSwapchainKHR s)
{
	struct swapchain_data *d;
	for (d = g_swapchains; d; d = d->next)
		if (d->swapchain == s)
			return d;
	return NULL;
}

/* ------------------------------------------------------------------ */

static void destroy_shadows(struct swapchain_data *sd)
{
	struct device_data *dd = sd->dd;
	uint32_t i;

	for (i = 0; i < sd->count; i++) {
		if (sd->copy_fence[i])
			dd->DestroyFence(dd->device, sd->copy_fence[i], NULL);
		if (sd->shadow[i])
			dd->DestroyImage(dd->device, sd->shadow[i], NULL);
		if (sd->memory[i])
			dd->FreeMemory(dd->device, sd->memory[i], NULL);
	}
	memset(sd->shadow, 0, sizeof(sd->shadow));
	memset(sd->memory, 0, sizeof(sd->memory));
	memset(sd->copy_fence, 0, sizeof(sd->copy_fence));
	sd->active = 0;
}

/* Build one shadow image per real image, plus the command buffer and
 * semaphore used to copy it in.  Returns 0 on any failure, in which case the
 * caller falls back to handing out the real images unchanged -- a tearing
 * swapchain is better than a dead one. */
static int build_shadows(struct swapchain_data *sd,
			 const VkSwapchainCreateInfoKHR *ci)
{
	struct device_data *dd = sd->dd;
	VkCommandBufferAllocateInfo cbi;
	uint32_t i, t;

	for (i = 0; i < sd->count; i++) {
		VkImageCreateInfo ici;
		VkMemoryRequirements mreq;
		VkMemoryAllocateInfo mai;

		memset(&ici, 0, sizeof(ici));
		ici.sType         = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
		ici.imageType     = VK_IMAGE_TYPE_2D;
		ici.format        = ci->imageFormat;
		ici.extent.width  = ci->imageExtent.width;
		ici.extent.height = ci->imageExtent.height;
		ici.extent.depth  = 1;
		ici.mipLevels     = 1;
		ici.arrayLayers   = ci->imageArrayLayers;
		ici.samples       = VK_SAMPLE_COUNT_1_BIT;
		ici.tiling        = VK_IMAGE_TILING_OPTIMAL;
		/* TRANSFER_SRC is ours; the rest is whatever the application
		 * asked the swapchain for, since it renders into these. */
		ici.usage         = ci->imageUsage | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
		ici.sharingMode   = ci->imageSharingMode;
		ici.queueFamilyIndexCount = ci->queueFamilyIndexCount;
		ici.pQueueFamilyIndices   = ci->pQueueFamilyIndices;
		ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

		if (dd->CreateImage(dd->device, &ici, NULL, &sd->shadow[i]) != VK_SUCCESS)
			return 0;

		dd->GetImageMemoryRequirements(dd->device, sd->shadow[i], &mreq);
		memset(&mai, 0, sizeof(mai));
		mai.sType           = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
		mai.allocationSize  = mreq.size;
		mai.memoryTypeIndex = dd->mem_props.memoryTypeCount;
		for (t = 0; t < dd->mem_props.memoryTypeCount; t++)
			if ((mreq.memoryTypeBits & (1u << t))
			    && (dd->mem_props.memoryTypes[t].propertyFlags
				& VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) {
				mai.memoryTypeIndex = t;
				break;
			}
		if (mai.memoryTypeIndex == dd->mem_props.memoryTypeCount)
			return 0;
		if (dd->AllocateMemory(dd->device, &mai, NULL, &sd->memory[i]) != VK_SUCCESS)
			return 0;
		if (dd->BindImageMemory(dd->device, sd->shadow[i], sd->memory[i], 0) != VK_SUCCESS)
			return 0;
	}

	memset(&cbi, 0, sizeof(cbi));
	cbi.sType              = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
	cbi.commandPool        = dd->pool;
	cbi.level              = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
	cbi.commandBufferCount = sd->count;
	if (dd->AllocateCommandBuffers(dd->device, &cbi, sd->cmd) != VK_SUCCESS)
		return 0;

	for (i = 0; i < sd->count; i++) {
		VkFenceCreateInfo fci;
		memset(&fci, 0, sizeof(fci));
		fci.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
		fci.flags = VK_FENCE_CREATE_SIGNALED_BIT;
		if (dd->CreateFence(dd->device, &fci, NULL, &sd->copy_fence[i]) != VK_SUCCESS)
			return 0;
	}

	sd->width  = ci->imageExtent.width;
	sd->height = ci->imageExtent.height;
	return 1;
}

/* shadow[idx] -> real[idx], recorded fresh each frame.  The application left
 * the shadow in PRESENT_SRC because as far as it knows that image is the
 * swapchain's. */
static void record_copy(struct swapchain_data *sd, uint32_t idx)
{
	struct device_data *dd = sd->dd;
	VkImageSubresourceRange range = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };
	VkCommandBufferBeginInfo bi;
	VkImageMemoryBarrier pre[2], post[2];
	VkImageCopy region;

	memset(&bi, 0, sizeof(bi));
	bi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
	bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
	dd->BeginCommandBuffer(sd->cmd[idx], &bi);

	memset(pre, 0, sizeof(pre));
	pre[0].sType            = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
	pre[0].oldLayout        = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
	pre[0].newLayout        = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
	pre[0].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	pre[0].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	pre[0].image            = sd->shadow[idx];
	pre[0].subresourceRange = range;
	pre[0].srcAccessMask    = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
	pre[0].dstAccessMask    = VK_ACCESS_TRANSFER_READ_BIT;

	/* UNDEFINED, not PRESENT_SRC: the copy overwrites every pixel, and the
	 * real image's previous contents are of no interest. */
	pre[1].sType            = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
	pre[1].oldLayout        = VK_IMAGE_LAYOUT_UNDEFINED;
	pre[1].newLayout        = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
	pre[1].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	pre[1].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	pre[1].image            = sd->real[idx];
	pre[1].subresourceRange = range;
	pre[1].dstAccessMask    = VK_ACCESS_TRANSFER_WRITE_BIT;

	dd->CmdPipelineBarrier(sd->cmd[idx],
			       VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
			       VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
			       0, NULL, 0, NULL, 2, pre);

	memset(&region, 0, sizeof(region));
	region.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	region.srcSubresource.layerCount = 1;
	region.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	region.dstSubresource.layerCount = 1;
	region.extent.width  = sd->width;
	region.extent.height = sd->height;
	region.extent.depth  = 1;
	dd->CmdCopyImage(sd->cmd[idx],
			 sd->shadow[idx], VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
			 sd->real[idx],   VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
			 1, &region);

	memset(post, 0, sizeof(post));
	post[0].sType            = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
	post[0].oldLayout        = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
	post[0].newLayout        = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
	post[0].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	post[0].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	post[0].image            = sd->real[idx];
	post[0].subresourceRange = range;
	post[0].srcAccessMask    = VK_ACCESS_TRANSFER_WRITE_BIT;

	/* Hand the shadow back in the layout the application believes it is
	 * in, so its next frame's barriers line up. */
	post[1].sType            = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
	post[1].oldLayout        = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
	post[1].newLayout        = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
	post[1].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	post[1].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	post[1].image            = sd->shadow[idx];
	post[1].subresourceRange = range;
	post[1].srcAccessMask    = VK_ACCESS_TRANSFER_READ_BIT;

	dd->CmdPipelineBarrier(sd->cmd[idx],
			       VK_PIPELINE_STAGE_TRANSFER_BIT,
			       VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0,
			       0, NULL, 0, NULL, 2, post);
	dd->EndCommandBuffer(sd->cmd[idx]);
}

/* ------------------------------------------------------------------ */

static VKAPI_ATTR VkResult VKAPI_CALL
layer_CreateSwapchainKHR(VkDevice device,
			 const VkSwapchainCreateInfoKHR *ci,
			 const VkAllocationCallbacks *alloc,
			 VkSwapchainKHR *out)
{
	struct device_data *dd;
	struct swapchain_data *sd;
	VkSwapchainCreateInfoKHR local;
	VkResult r;
	uint32_t n = 0;

	pthread_mutex_lock(&g_lock);
	dd = find_device(device);
	pthread_mutex_unlock(&g_lock);
	if (!dd)
		return VK_ERROR_INITIALIZATION_FAILED;

	/* The real images become copy destinations. */
	local = *ci;
	local.imageUsage |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;

	r = dd->CreateSwapchainKHR(device, &local, alloc, out);
	if (r != VK_SUCCESS)
		return r;

	sd = calloc(1, sizeof(*sd));
	if (!sd)
		return r;
	sd->swapchain = *out;
	sd->dd        = dd;

	if (dd->GetSwapchainImagesKHR(device, *out, &n, NULL) != VK_SUCCESS
	    || n == 0 || n > MAX_SWAPCHAIN_IMAGES) {
		dbg("swapchain has %u images, passing through", n);
		free(sd);
		return r;
	}
	sd->count = n;
	if (dd->GetSwapchainImagesKHR(device, *out, &n, sd->real) != VK_SUCCESS) {
		free(sd);
		return r;
	}

	if (!build_shadows(sd, ci)) {
		dbg("swapchain %ux%u: shadow setup failed, passing through",
		    ci->imageExtent.width, ci->imageExtent.height);
		destroy_shadows(sd);
		free(sd);
		return r;   /* passthrough: app gets the real images */
	}
	sd->active = 1;
	dbg("swapchain %ux%u: shadowing %u image(s)",
	    ci->imageExtent.width, ci->imageExtent.height, sd->count);

	pthread_mutex_lock(&g_lock);
	sd->next     = g_swapchains;
	g_swapchains = sd;
	pthread_mutex_unlock(&g_lock);
	return r;
}

static VKAPI_ATTR VkResult VKAPI_CALL
layer_GetSwapchainImagesKHR(VkDevice device, VkSwapchainKHR swapchain,
			    uint32_t *count, VkImage *images)
{
	struct device_data *dd;
	struct swapchain_data *sd;
	uint32_t i, n;

	pthread_mutex_lock(&g_lock);
	dd = find_device(device);
	sd = find_swapchain(swapchain);
	pthread_mutex_unlock(&g_lock);
	if (!dd)
		return VK_ERROR_INITIALIZATION_FAILED;
	if (!sd || !sd->active)
		return dd->GetSwapchainImagesKHR(device, swapchain, count, images);

	if (!images) {
		*count = sd->count;
		return VK_SUCCESS;
	}
	n = *count < sd->count ? *count : sd->count;
	for (i = 0; i < n; i++)
		images[i] = sd->shadow[i];
	*count = n;
	return n < sd->count ? VK_INCOMPLETE : VK_SUCCESS;
}

/* The copy runs *after* the real present, and that ordering is the whole
 * point.  vkQueuePresentKHR returns at a vblank V with the flip to this image
 * queued for V+1, so the image is not scanned out during [V, V+1] -- the other
 * one is.  Copying inside that gap writes a buffer nobody is reading, and the
 * ~2.4ms copy finishes well before V+1, when the flip makes it visible.
 *
 * Copying before the present, which is the obvious placement, lands in exactly
 * the window where the destination *is* on screen, and tears a band as tall as
 * the fraction of the frame the application spent rendering.
 *
 * Writing an image after presenting it is not legal Vulkan.  It is correct
 * here only because this driver latches the flip a vblank late, which is the
 * defect being worked around.
 */
static VKAPI_ATTR VkResult VKAPI_CALL
layer_QueuePresentKHR(VkQueue queue, const VkPresentInfoKHR *pi)
{
	struct device_data *dd = NULL;
	struct swapchain_data *sd;
	uint32_t i;
	VkResult r;

	pthread_mutex_lock(&g_lock);
	for (i = 0; i < pi->swapchainCount && !dd; i++) {
		sd = find_swapchain(pi->pSwapchains[i]);
		if (sd)
			dd = sd->dd;
	}
	if (!dd)
		for (sd = g_swapchains; sd; sd = sd->next)
			if (sd->dd) {
				dd = sd->dd;
				break;
			}
	pthread_mutex_unlock(&g_lock);
	if (!dd)
		return VK_ERROR_INITIALIZATION_FAILED;

	/* Straight through: the application's semaphores already order this
	 * against its rendering. */
	r = dd->QueuePresentKHR(queue, pi);

	for (i = 0; i < pi->swapchainCount; i++) {
		VkSubmitInfo si;
		uint32_t idx;

		pthread_mutex_lock(&g_lock);
		sd = find_swapchain(pi->pSwapchains[i]);
		pthread_mutex_unlock(&g_lock);
		if (!sd || !sd->active)
			continue;

		idx = pi->pImageIndices[i];
		if (idx >= sd->count)
			continue;

		/* Two frames since this image was last copied, so the fence is
		 * long signalled; the wait only guards against re-recording a
		 * command buffer still in flight. */
		dd->WaitForFences(dd->device, 1, &sd->copy_fence[idx],
				  VK_TRUE, UINT64_MAX);
		dd->ResetFences(dd->device, 1, &sd->copy_fence[idx]);

		record_copy(sd, idx);

		memset(&si, 0, sizeof(si));
		si.sType              = VK_STRUCTURE_TYPE_SUBMIT_INFO;
		si.commandBufferCount = 1;
		si.pCommandBuffers    = &sd->cmd[idx];
		dd->QueueSubmit(queue, 1, &si, sd->copy_fence[idx]);
	}

	return r;
}

static VKAPI_ATTR void VKAPI_CALL
layer_DestroySwapchainKHR(VkDevice device, VkSwapchainKHR swapchain,
			  const VkAllocationCallbacks *alloc)
{
	struct device_data *dd;
	struct swapchain_data *sd, **pp;

	pthread_mutex_lock(&g_lock);
	dd = find_device(device);
	for (pp = &g_swapchains; *pp; pp = &(*pp)->next)
		if ((*pp)->swapchain == swapchain) {
			sd  = *pp;
			*pp = sd->next;
			pthread_mutex_unlock(&g_lock);
			destroy_shadows(sd);
			free(sd);
			goto done;
		}
	pthread_mutex_unlock(&g_lock);
done:
	if (dd)
		dd->DestroySwapchainKHR(device, swapchain, alloc);
}

/* ------------------------------------------------------------------ */

static VKAPI_ATTR VkResult VKAPI_CALL
layer_CreateInstance(const VkInstanceCreateInfo *ci,
		     const VkAllocationCallbacks *alloc,
		     VkInstance *out)
{
	VkLayerInstanceCreateInfo *chain = (VkLayerInstanceCreateInfo *)ci->pNext;
	PFN_vkGetInstanceProcAddr gpa;
	PFN_vkCreateInstance create;
	struct instance_data *id;
	VkResult r;

	while (chain && !(chain->sType == VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO
			  && chain->function == VK_LAYER_LINK_INFO))
		chain = (VkLayerInstanceCreateInfo *)chain->pNext;
	if (!chain)
		return VK_ERROR_INITIALIZATION_FAILED;

	gpa = chain->u.pLayerInfo->pfnNextGetInstanceProcAddr;
	chain->u.pLayerInfo = chain->u.pLayerInfo->pNext;

	create = (PFN_vkCreateInstance)gpa(NULL, "vkCreateInstance");
	if (!create)
		return VK_ERROR_INITIALIZATION_FAILED;
	r = create(ci, alloc, out);
	if (r != VK_SUCCESS)
		return r;

	id = calloc(1, sizeof(*id));
	if (!id)
		return VK_ERROR_OUT_OF_HOST_MEMORY;
	id->instance = *out;
	id->gpa      = gpa;
	id->DestroyInstance = (PFN_vkDestroyInstance)gpa(*out, "vkDestroyInstance");
	id->GetPhysicalDeviceMemoryProperties =
		(PFN_vkGetPhysicalDeviceMemoryProperties)
		gpa(*out, "vkGetPhysicalDeviceMemoryProperties");

	pthread_mutex_lock(&g_lock);
	id->next    = g_instances;
	g_instances = id;
	pthread_mutex_unlock(&g_lock);
	return VK_SUCCESS;
}

static VKAPI_ATTR void VKAPI_CALL
layer_DestroyInstance(VkInstance instance, const VkAllocationCallbacks *alloc)
{
	struct instance_data *id, **pp;
	PFN_vkDestroyInstance destroy = NULL;

	pthread_mutex_lock(&g_lock);
	for (pp = &g_instances; *pp; pp = &(*pp)->next)
		if ((*pp)->instance == instance) {
			id      = *pp;
			*pp     = id->next;
			destroy = id->DestroyInstance;
			free(id);
			break;
		}
	pthread_mutex_unlock(&g_lock);
	if (destroy)
		destroy(instance, alloc);
}

#define GD(name) dd->name = (PFN_vk##name)gdpa(*out, "vk" #name)

static VKAPI_ATTR VkResult VKAPI_CALL
layer_CreateDevice(VkPhysicalDevice gpu, const VkDeviceCreateInfo *ci,
		   const VkAllocationCallbacks *alloc, VkDevice *out)
{
	VkLayerDeviceCreateInfo *chain = (VkLayerDeviceCreateInfo *)ci->pNext;
	PFN_vkGetInstanceProcAddr gipa;
	PFN_vkGetDeviceProcAddr gdpa;
	PFN_vkCreateDevice create;
	struct device_data *dd;
	struct instance_data *id;
	VkCommandPoolCreateInfo pci;
	VkResult r;

	while (chain && !(chain->sType == VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO
			  && chain->function == VK_LAYER_LINK_INFO))
		chain = (VkLayerDeviceCreateInfo *)chain->pNext;
	if (!chain)
		return VK_ERROR_INITIALIZATION_FAILED;

	gipa = chain->u.pLayerInfo->pfnNextGetInstanceProcAddr;
	gdpa = chain->u.pLayerInfo->pfnNextGetDeviceProcAddr;
	chain->u.pLayerInfo = chain->u.pLayerInfo->pNext;

	create = (PFN_vkCreateDevice)gipa(NULL, "vkCreateDevice");
	if (!create)
		return VK_ERROR_INITIALIZATION_FAILED;
	r = create(gpu, ci, alloc, out);
	if (r != VK_SUCCESS)
		return r;

	dd = calloc(1, sizeof(*dd));
	if (!dd)
		return VK_ERROR_OUT_OF_HOST_MEMORY;
	dd->device = *out;
	dd->gpu    = gpu;
	dd->gdpa   = gdpa;
	dd->queue_family = ci->queueCreateInfoCount
		? ci->pQueueCreateInfos[0].queueFamilyIndex : 0;

	GD(DestroyDevice);
	GD(CreateSwapchainKHR);
	GD(DestroySwapchainKHR);
	GD(GetSwapchainImagesKHR);
	GD(AcquireNextImageKHR);
	GD(QueuePresentKHR);
	GD(CreateImage);
	GD(DestroyImage);
	GD(GetImageMemoryRequirements);
	GD(AllocateMemory);
	GD(FreeMemory);
	GD(BindImageMemory);
	GD(CreateCommandPool);
	GD(DestroyCommandPool);
	GD(AllocateCommandBuffers);
	GD(BeginCommandBuffer);
	GD(EndCommandBuffer);
	GD(CmdPipelineBarrier);
	GD(CmdCopyImage);
	GD(CreateFence);
	GD(DestroyFence);
	GD(WaitForFences);
	GD(ResetFences);
	GD(QueueSubmit);

	pthread_mutex_lock(&g_lock);
	for (id = g_instances; id; id = id->next)
		if (id->GetPhysicalDeviceMemoryProperties)
			break;
	pthread_mutex_unlock(&g_lock);
	if (id) {
		dd->id = id;
		id->GetPhysicalDeviceMemoryProperties(gpu, &dd->mem_props);
	}

	memset(&pci, 0, sizeof(pci));
	pci.sType            = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
	pci.flags            = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
	pci.queueFamilyIndex = dd->queue_family;
	dd->CreateCommandPool(*out, &pci, NULL, &dd->pool);

	pthread_mutex_lock(&g_lock);
	dd->next  = g_devices;
	g_devices = dd;
	pthread_mutex_unlock(&g_lock);
	return VK_SUCCESS;
}

static VKAPI_ATTR void VKAPI_CALL
layer_DestroyDevice(VkDevice device, const VkAllocationCallbacks *alloc)
{
	struct device_data *dd = NULL, **pp;
	PFN_vkDestroyDevice destroy = NULL;

	pthread_mutex_lock(&g_lock);
	for (pp = &g_devices; *pp; pp = &(*pp)->next)
		if ((*pp)->device == device) {
			dd  = *pp;
			*pp = dd->next;
			break;
		}
	pthread_mutex_unlock(&g_lock);

	if (dd) {
		destroy = dd->DestroyDevice;
		if (dd->pool)
			dd->DestroyCommandPool(device, dd->pool, NULL);
		free(dd);
	}
	if (destroy)
		destroy(device, alloc);
}

/* ------------------------------------------------------------------ */

#define HOOK(name) if (!strcmp(pName, "vk" #name)) \
	return (PFN_vkVoidFunction)layer_##name

static VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
layer_GetDeviceProcAddr(VkDevice device, const char *pName)
{
	struct device_data *dd;

	HOOK(GetDeviceProcAddr);
	HOOK(DestroyDevice);
	HOOK(CreateSwapchainKHR);
	HOOK(DestroySwapchainKHR);
	HOOK(GetSwapchainImagesKHR);
	HOOK(QueuePresentKHR);

	pthread_mutex_lock(&g_lock);
	dd = find_device(device);
	pthread_mutex_unlock(&g_lock);
	return dd ? dd->gdpa(device, pName) : NULL;
}

static VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
layer_GetInstanceProcAddr(VkInstance instance, const char *pName)
{
	struct instance_data *id;

	HOOK(GetInstanceProcAddr);
	HOOK(CreateInstance);
	HOOK(DestroyInstance);
	HOOK(CreateDevice);
	HOOK(GetDeviceProcAddr);
	HOOK(DestroyDevice);
	HOOK(CreateSwapchainKHR);
	HOOK(DestroySwapchainKHR);
	HOOK(GetSwapchainImagesKHR);
	HOOK(QueuePresentKHR);

	pthread_mutex_lock(&g_lock);
	id = find_instance(instance);
	pthread_mutex_unlock(&g_lock);
	return id ? id->gpa(instance, pName) : NULL;
}

VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
vkGetInstanceProcAddr(VkInstance instance, const char *pName)
{
	return layer_GetInstanceProcAddr(instance, pName);
}

VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
vkGetDeviceProcAddr(VkDevice device, const char *pName)
{
	return layer_GetDeviceProcAddr(device, pName);
}

VK_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL
vkNegotiateLoaderLayerInterfaceVersion(VkNegotiateLayerInterface *iface)
{
	if (iface->loaderLayerInterfaceVersion < 2)
		return VK_ERROR_INITIALIZATION_FAILED;
	iface->loaderLayerInterfaceVersion = 2;
	iface->pfnGetInstanceProcAddr      = layer_GetInstanceProcAddr;
	iface->pfnGetDeviceProcAddr        = layer_GetDeviceProcAddr;
	iface->pfnGetPhysicalDeviceProcAddr = NULL;
	return VK_SUCCESS;
}
