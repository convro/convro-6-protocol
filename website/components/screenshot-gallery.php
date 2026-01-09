<?php
$screenshots = getScreenshots();
$total = count($screenshots);

// Only show gallery if screenshots exist
if ($total === 0) {
    return;
}
?>

<!-- Screenshot Gallery Section -->
<section id="app-preview" class="py-20 bg-white dark:bg-slate-900">
    <div class="container mx-auto px-4">
        <!-- Section Header -->
        <div class="text-center mb-12">
            <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                See Convro in Action
            </h2>
            <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                Preview the Convro messenger built on C6P. Secure, private, and production-ready.
            </p>
        </div>

        <!-- Gallery -->
        <div x-data="galleryApp()" class="max-w-5xl mx-auto">
            <div class="bg-gradient-to-br from-slate-900 to-slate-800 rounded-2xl shadow-2xl overflow-hidden border border-slate-700 p-4 md:p-8">
                <!-- Main Image Display -->
                <div class="relative bg-black rounded-xl overflow-hidden mb-6" style="aspect-ratio: 16/9;">
                    <?php foreach ($screenshots as $index => $screenshot): ?>
                        <img
                            src="<?= e($screenshot['path']) ?>"
                            alt="<?= e($screenshot['name']) ?>"
                            x-show="currentIndex === <?= $index ?>"
                            x-transition:enter="transition ease-out duration-300"
                            x-transition:enter-start="opacity-0 transform scale-95"
                            x-transition:enter-end="opacity-100 transform scale-100"
                            x-transition:leave="transition ease-in duration-200"
                            x-transition:leave-start="opacity-100 transform scale-100"
                            x-transition:leave-end="opacity-0 transform scale-95"
                            class="absolute inset-0 w-full h-full object-contain"
                            loading="lazy"
                        >
                    <?php endforeach; ?>

                    <!-- Loading State -->
                    <div
                        x-show="currentIndex === null"
                        class="absolute inset-0 flex items-center justify-center bg-slate-900"
                    >
                        <div class="animate-spin rounded-full h-12 w-12 border-t-2 border-b-2 border-blue-500"></div>
                    </div>
                </div>

                <!-- Controls -->
                <div class="flex items-center justify-between gap-4 mb-6">
                    <!-- Previous Button -->
                    <button
                        @click="prev()"
                        :disabled="currentIndex === 0"
                        :class="currentIndex === 0 ? 'opacity-50 cursor-not-allowed' : 'hover:bg-white/20'"
                        class="flex items-center justify-center w-12 h-12 rounded-full bg-white/10 backdrop-blur-sm transition-all disabled:hover:bg-white/10"
                    >
                        <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
                        </svg>
                    </button>

                    <!-- Counter & Caption -->
                    <div class="flex-1 text-center">
                        <div class="text-white font-mono text-lg font-bold mb-1">
                            <span x-text="currentIndex + 1"></span> / <span><?= $total ?></span>
                        </div>
                        <?php foreach ($screenshots as $index => $screenshot): ?>
                            <div
                                x-show="currentIndex === <?= $index ?>"
                                x-transition
                                class="text-sm text-gray-300"
                            >
                                <?= e($screenshot['name']) ?>
                            </div>
                        <?php endforeach; ?>
                    </div>

                    <!-- Next Button -->
                    <button
                        @click="next()"
                        :disabled="currentIndex === <?= $total - 1 ?>"
                        :class="currentIndex === <?= $total - 1 ?> ? 'opacity-50 cursor-not-allowed' : 'hover:bg-white/20'"
                        class="flex items-center justify-center w-12 h-12 rounded-full bg-white/10 backdrop-blur-sm transition-all disabled:hover:bg-white/10"
                    >
                        <svg class="w-6 h-6 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
                        </svg>
                    </button>
                </div>

                <!-- Thumbnails -->
                <div class="relative">
                    <div class="flex gap-2 overflow-x-auto pb-2 scrollbar-thin scrollbar-thumb-slate-600 scrollbar-track-slate-800">
                        <?php foreach ($screenshots as $index => $screenshot): ?>
                            <button
                                @click="currentIndex = <?= $index ?>"
                                :class="currentIndex === <?= $index ?> ? 'ring-2 ring-blue-500 opacity-100' : 'opacity-60 hover:opacity-100'"
                                class="flex-shrink-0 w-24 h-16 rounded-lg overflow-hidden transition-all bg-black"
                            >
                                <img
                                    src="<?= e($screenshot['path']) ?>"
                                    alt="Thumbnail <?= $index + 1 ?>"
                                    class="w-full h-full object-cover"
                                    loading="lazy"
                                >
                            </button>
                        <?php endforeach; ?>
                    </div>
                </div>

                <!-- Keyboard Navigation Hint -->
                <div class="mt-4 text-center text-xs text-gray-400">
                    <kbd class="px-2 py-1 bg-slate-700 rounded">←</kbd>
                    <kbd class="px-2 py-1 bg-slate-700 rounded mx-2">→</kbd>
                    Navigate with arrow keys
                </div>
            </div>
        </div>
    </div>
</section>

<script>
function galleryApp() {
    return {
        currentIndex: 0,
        total: <?= $total ?>,

        init() {
            // Keyboard navigation
            document.addEventListener('keydown', (e) => {
                if (e.key === 'ArrowLeft') this.prev();
                if (e.key === 'ArrowRight') this.next();
            });

            // Preload images
            this.preloadImages();
        },

        next() {
            if (this.currentIndex < this.total - 1) {
                this.currentIndex++;
            }
        },

        prev() {
            if (this.currentIndex > 0) {
                this.currentIndex--;
            }
        },

        preloadImages() {
            // Preload next/prev images for smooth transitions
            const screenshots = <?= json_encode(array_column($screenshots, 'path')) ?>;
            screenshots.forEach(src => {
                const img = new Image();
                img.src = src;
            });
        }
    }
}
</script>
