<?php
$status = getGitHubStatus();
?>

<!-- Hero Section -->
<section class="relative overflow-hidden bg-gradient-to-br from-blue-50 via-white to-purple-50 dark:from-slate-900 dark:via-slate-800 dark:to-slate-900 py-20 md:py-32">
    <!-- Background Pattern -->
    <div class="absolute inset-0 opacity-30 dark:opacity-10">
        <div class="absolute inset-0" style="background-image: radial-gradient(circle at 1px 1px, rgb(59 130 246 / 0.15) 1px, transparent 0); background-size: 40px 40px;"></div>
    </div>

    <div class="container mx-auto px-4 relative z-10">
        <div class="grid lg:grid-cols-2 gap-12 items-center">
            <!-- Left: Content -->
            <div>
                <!-- Badge -->
                <div class="inline-flex items-center gap-2 px-4 py-2 mb-6 bg-white dark:bg-slate-800 rounded-full shadow-sm border border-gray-200 dark:border-gray-700">
                    <?= statusBadge($status['conclusion']) ?>
                    <span class="text-sm text-gray-600 dark:text-gray-400">
                        All <?= e($status['ci_jobs']) ?> CI Jobs Passing
                    </span>
                </div>

                <!-- Headline -->
                <h1 class="text-4xl md:text-5xl lg:text-6xl font-bold text-gray-900 dark:text-white mb-6 leading-tight">
                    Production-Grade
                    <span class="text-transparent bg-clip-text bg-gradient-to-r from-blue-600 to-purple-600">
                        E2E Encryption
                    </span>
                </h1>

                <!-- Subheadline -->
                <p class="text-lg md:text-xl text-gray-600 dark:text-gray-300 mb-8 leading-relaxed">
                    Audit-ready messaging protocol with authenticated prekey handshakes, per-message forward secrecy, and replay resistance. Built for security-critical applications.
                </p>

                <!-- CTAs -->
                <div class="flex flex-col sm:flex-row gap-4 mb-8">
                    <a
                        href="<?= THREAT_MODEL_PDF ?>"
                        class="inline-flex items-center justify-center px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg shadow-lg hover:shadow-xl transition-all hover:-translate-y-0.5"
                    >
                        <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                        </svg>
                        Threat Model (7p)
                    </a>
                    <a
                        href="<?= DOCS_URL ?>"
                        class="inline-flex items-center justify-center px-6 py-3 bg-white dark:bg-slate-800 hover:bg-gray-50 dark:hover:bg-slate-700 text-gray-900 dark:text-white font-semibold rounded-lg shadow border border-gray-300 dark:border-gray-700 hover:shadow-md transition-all"
                    >
                        Read Documentation
                        <svg class="w-5 h-5 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6"/>
                        </svg>
                    </a>
                </div>

                <!-- Quick Stats -->
                <div class="grid grid-cols-3 gap-4 pt-8 border-t border-gray-200 dark:border-gray-700">
                    <div>
                        <div class="text-2xl md:text-3xl font-bold text-gray-900 dark:text-white">
                            <?= e($status['tests_passing']) ?>
                        </div>
                        <div class="text-sm text-gray-500 dark:text-gray-400">
                            Tests Passing
                        </div>
                    </div>
                    <div>
                        <div class="text-2xl md:text-3xl font-bold text-gray-900 dark:text-white">
                            <?= e($status['warnings']) ?>
                        </div>
                        <div class="text-sm text-gray-500 dark:text-gray-400">
                            Warnings
                        </div>
                    </div>
                    <div>
                        <div class="text-2xl md:text-3xl font-bold text-gray-900 dark:text-white">
                            <?= MSRV ?>
                        </div>
                        <div class="text-sm text-gray-500 dark:text-gray-400">
                            MSRV Rust
                        </div>
                    </div>
                </div>
            </div>

            <!-- Right: Live Terminal -->
            <div class="hidden lg:block">
                <div class="bg-slate-900 rounded-xl shadow-2xl overflow-hidden border border-slate-700">
                    <!-- Terminal Header -->
                    <div class="flex items-center gap-2 px-4 py-3 bg-slate-800 border-b border-slate-700">
                        <div class="flex gap-1.5">
                            <div class="w-3 h-3 rounded-full bg-red-500"></div>
                            <div class="w-3 h-3 rounded-full bg-yellow-500"></div>
                            <div class="w-3 h-3 rounded-full bg-green-500"></div>
                        </div>
                        <div class="flex-1 text-center text-sm text-gray-400 font-mono">
                            cargo test --workspace
                        </div>
                    </div>

                    <!-- Terminal Content -->
                    <div class="p-6 font-mono text-sm space-y-2 h-96 overflow-hidden">
                        <div class="text-green-400">$ cargo test --workspace</div>
                        <div class="text-gray-400 text-xs">   Compiling c6p-crypto v0.1.0</div>
                        <div class="text-gray-400 text-xs">   Compiling c6p-identity v0.1.0</div>
                        <div class="text-gray-400 text-xs">   Compiling c6p-handshake v0.1.0</div>
                        <div class="text-gray-400 text-xs">   Compiling c6p-sessions v0.1.0</div>
                        <div class="mt-4"></div>
                        <div class="text-blue-300">Running unittests src/lib.rs (c6p-crypto)</div>
                        <div class="text-green-400">✓ test_key_schedule</div>
                        <div class="text-green-400">✓ test_nonce_derivation</div>
                        <div class="text-green-400">✓ test_aead_encryption</div>
                        <div class="text-gray-500 text-xs">test result: ok. 8 passed; 0 failed</div>
                        <div class="mt-2"></div>
                        <div class="text-blue-300">Running unittests src/lib.rs (c6p-handshake)</div>
                        <div class="text-green-400">✓ test_offer_construction</div>
                        <div class="text-green-400">✓ test_accept_construction</div>
                        <div class="text-green-400">✓ test_key_confirmation</div>
                        <div class="text-gray-500 text-xs">test result: ok. 21 passed; 0 failed</div>
                        <div class="mt-2"></div>
                        <div class="text-blue-300">Running unittests src/lib.rs (c6p-sessions)</div>
                        <div class="text-green-400">✓ test_send_ratchet</div>
                        <div class="text-green-400">✓ test_receive_ratchet</div>
                        <div class="text-green-400">✓ test_replay_detection</div>
                        <div class="text-gray-500 text-xs">test result: ok. 57 passed; 0 failed</div>
                        <div class="mt-4"></div>
                        <div class="text-white font-bold">
                            test result: <span class="text-green-400">ok</span>. <?= TESTS_PASSING ?> passed; 0 failed
                        </div>
                        <div class="mt-2"></div>
                        <div class="text-green-400 animate-pulse">█</div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</section>
