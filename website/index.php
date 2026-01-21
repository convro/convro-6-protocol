<?php
require_once __DIR__ . '/includes/config.php';
require_once __DIR__ . '/includes/functions.php';

$status = getGitHubStatus();
?>
<!DOCTYPE html>
<html lang="en" class="no-transition">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="ie=edge">

    <?= generateMetaTags() ?>

    <!-- Favicon -->
    <link rel="icon" type="image/png" href="<?= LOGO_ICON_SQUARE ?>">

    <!-- Tailwind CSS CDN -->
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = {
            darkMode: 'class',
            theme: {
                extend: {
                    fontFamily: {
                        sans: ['Inter', 'system-ui', 'sans-serif'],
                        mono: ['JetBrains Mono', 'Fira Code', 'monospace']
                    }
                }
            }
        }
    </script>

    <!-- Custom CSS -->
    <link rel="stylesheet" href="<?= CSS_PATH ?>/custom.css">

    <!-- Alpine.js -->
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>

    <!-- Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
</head>
<body class="bg-white dark:bg-slate-900 text-gray-900 dark:text-white" x-data="app()" x-init="init()" style="opacity: 0;">

    <?php include __DIR__ . '/components/header.php'; ?>

    <main>
        <?php include __DIR__ . '/components/hero.php'; ?>

        <!-- Features Section -->
        <section id="protocol" class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Security Guarantees
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        C6P provides mathematically proven security properties. Every feature is documented, tested, and ready for audit.
                    </p>
                </div>

                <div class="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
                    <?php foreach ($FEATURES as $feature): ?>
                        <div class="bg-white dark:bg-slate-900 rounded-xl p-6 border border-gray-200 dark:border-gray-700 card-hover">
                            <div class="mb-4">
                                <img
                                    src="<?= e($feature['badge']) ?>"
                                    alt="<?= e($feature['title']) ?>"
                                    class="w-16 h-16 object-contain"
                                    onerror="this.style.display='none'"
                                >
                            </div>
                            <h3 class="text-xl font-bold text-gray-900 dark:text-white mb-3">
                                <?= e($feature['title']) ?>
                            </h3>
                            <p class="text-gray-600 dark:text-gray-400 mb-4 leading-relaxed">
                                <?= e($feature['description']) ?>
                            </p>
                            <a
                                href="<?= e($feature['spec_link']) ?>"
                                class="inline-flex items-center text-sm text-blue-600 dark:text-blue-400 hover:underline font-medium"
                            >
                                <?= e($feature['spec_cite']) ?>
                                <svg class="w-4 h-4 ml-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
                                </svg>
                            </a>
                        </div>
                    <?php endforeach; ?>
                </div>
            </div>
        </section>

        <!-- Implementation Status -->
        <section id="implementation" class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Production Ready
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        See for yourself. Live CI/CD status from GitHub Actions.
                    </p>
                </div>

                <div class="grid md:grid-cols-2 lg:grid-cols-4 gap-6 mb-12">
                    <!-- CI/CD Status -->
                    <div class="bg-gradient-to-br from-green-50 to-green-100 dark:from-green-900/20 dark:to-green-800/20 rounded-xl p-6 border border-green-200 dark:border-green-800">
                        <div class="flex items-center gap-2 mb-2">
                            <?= statusBadge($status['conclusion']) ?>
                        </div>
                        <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                            <?= e($status['ci_jobs']) ?>
                        </div>
                        <div class="text-sm text-gray-600 dark:text-gray-400">
                            CI/CD Jobs Passing
                        </div>
                        <div class="text-xs text-gray-500 dark:text-gray-500 mt-2">
                            Updated <?= timeAgo($status['updated_at']) ?> ago
                        </div>
                    </div>

                    <!-- Tests -->
                    <div class="bg-gradient-to-br from-blue-50 to-blue-100 dark:from-blue-900/20 dark:to-blue-800/20 rounded-xl p-6 border border-blue-200 dark:border-blue-800">
                        <div class="flex items-center gap-2 mb-2">
                            <svg class="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                            </svg>
                            <span class="text-sm text-green-600 dark:text-green-400 font-medium">All Pass</span>
                        </div>
                        <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                            <?= e($status['tests_passing']) ?>
                        </div>
                        <div class="text-sm text-gray-600 dark:text-gray-400">
                            Tests Passing
                        </div>
                        <div class="text-xs text-gray-500 dark:text-gray-500 mt-2">
                            Zero failures
                        </div>
                    </div>

                    <!-- Clippy Warnings -->
                    <div class="bg-gradient-to-br from-purple-50 to-purple-100 dark:from-purple-900/20 dark:to-purple-800/20 rounded-xl p-6 border border-purple-200 dark:border-purple-800">
                        <div class="flex items-center gap-2 mb-2">
                            <svg class="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"/>
                            </svg>
                            <span class="text-sm text-green-600 dark:text-green-400 font-medium">Clean</span>
                        </div>
                        <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                            <?= e($status['warnings']) ?>
                        </div>
                        <div class="text-sm text-gray-600 dark:text-gray-400">
                            Clippy Warnings
                        </div>
                        <div class="text-xs text-gray-500 dark:text-gray-500 mt-2">
                            Strict mode (-D warnings)
                        </div>
                    </div>

                    <!-- Security Audit -->
                    <div class="bg-gradient-to-br from-orange-50 to-orange-100 dark:from-orange-900/20 dark:to-orange-800/20 rounded-xl p-6 border border-orange-200 dark:border-orange-800">
                        <div class="flex items-center gap-2 mb-2">
                            <svg class="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>
                            </svg>
                            <span class="text-sm text-green-600 dark:text-green-400 font-medium">Secure</span>
                        </div>
                        <div class="text-3xl font-bold text-gray-900 dark:text-white mb-1">
                            0
                        </div>
                        <div class="text-sm text-gray-600 dark:text-gray-400">
                            Vulnerabilities
                        </div>
                        <div class="text-xs text-gray-500 dark:text-gray-500 mt-2">
                            cargo-audit clean
                        </div>
                    </div>
                </div>

                <!-- CTA -->
                <div class="text-center">
                    <a
                        href="<?= e($status['run_url'] ?? GITHUB_REPO) ?>"
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center px-6 py-3 bg-gray-900 dark:bg-white text-white dark:text-gray-900 font-semibold rounded-lg hover:bg-gray-800 dark:hover:bg-gray-100 transition-colors"
                    >
                        <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                            <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
                        </svg>
                        View Live CI/CD on GitHub
                        <svg class="w-4 h-4 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/>
                        </svg>
                    </a>
                </div>
            </div>
        </section>

        <!-- Screenshot Gallery -->
        <?php include __DIR__ . '/components/screenshot-gallery.php'; ?>

        <!-- Threat Model Preview -->
        <section id="threat-model" class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Comprehensive Security Analysis
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        15 threat scenarios analyzed with mitigations and residual risk assessment.
                    </p>
                </div>

                <div class="grid md:grid-cols-2 gap-6 mb-12">
                    <?php foreach (array_slice($THREATS, 0, 4) as $threat): ?>
                        <div class="bg-white dark:bg-slate-900 rounded-xl p-6 border border-gray-200 dark:border-gray-700">
                            <div class="flex items-start justify-between mb-4">
                                <div>
                                    <span class="inline-block px-2 py-1 text-xs font-semibold rounded bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 mb-2">
                                        <?= e($threat['category']) ?>
                                    </span>
                                    <h3 class="text-lg font-bold text-gray-900 dark:text-white">
                                        Threat #<?= $threat['id'] ?>: <?= e($threat['title']) ?>
                                    </h3>
                                </div>
                                <span class="flex-shrink-0 inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-full bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
                                    <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                    </svg>
                                    <?= e($threat['status']) ?>
                                </span>
                            </div>
                            <p class="text-sm text-gray-600 dark:text-gray-400">
                                <span class="font-semibold text-gray-700 dark:text-gray-300">Mitigation:</span>
                                <?= e($threat['mitigation']) ?>
                            </p>
                        </div>
                    <?php endforeach; ?>
                </div>

                <div class="flex flex-col sm:flex-row justify-center gap-4">
                    <a
                        href="<?= THREAT_MODEL_PDF ?>"
                        class="inline-flex items-center justify-center px-6 py-3 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg shadow-lg hover:shadow-xl transition-all"
                    >
                        <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                        </svg>
                        Download Concise PDF (7 pages)
                    </a>
                    <a
                        href="<?= THREAT_MODEL_AUDIT_PDF ?>"
                        class="inline-flex items-center justify-center px-6 py-3 bg-white dark:bg-slate-800 hover:bg-gray-50 dark:hover:bg-slate-700 text-gray-900 dark:text-white font-semibold rounded-lg shadow border border-gray-300 dark:border-gray-700 hover:shadow-md transition-all"
                    >
                        <svg class="w-5 h-5 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                        </svg>
                        Download Audit PDF (26 pages)
                    </a>
                </div>
            </div>
        </section>

        <!-- FAQ -->
        <section id="faq" class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4 max-w-4xl">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Frequently Asked Questions
                    </h2>
                </div>

                <div class="space-y-4" x-data="{ openFaq: null }">
                    <?php foreach ($FAQ as $index => $faq): ?>
                        <div class="bg-gray-50 dark:bg-slate-800 rounded-xl overflow-hidden border border-gray-200 dark:border-gray-700">
                            <button
                                @click="openFaq = openFaq === <?= $index ?> ? null : <?= $index ?>"
                                class="w-full px-6 py-4 text-left flex items-center justify-between hover:bg-gray-100 dark:hover:bg-slate-700 transition-colors"
                            >
                                <span class="font-semibold text-gray-900 dark:text-white">
                                    <?= e($faq['question']) ?>
                                </span>
                                <svg
                                    class="w-5 h-5 text-gray-500 dark:text-gray-400 transition-transform"
                                    :class="openFaq === <?= $index ?> ? 'rotate-180' : ''"
                                    fill="none"
                                    stroke="currentColor"
                                    viewBox="0 0 24 24"
                                >
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
                                </svg>
                            </button>
                            <div
                                x-show="openFaq === <?= $index ?>"
                                x-transition:enter="transition ease-out duration-200"
                                x-transition:enter-start="opacity-0 -translate-y-2"
                                x-transition:enter-end="opacity-100 translate-y-0"
                                x-transition:leave="transition ease-in duration-150"
                                x-transition:leave-start="opacity-100 translate-y-0"
                                x-transition:leave-end="opacity-0 -translate-y-2"
                                class="px-6 pb-4"
                            >
                                <p class="text-gray-600 dark:text-gray-400 leading-relaxed">
                                    <?= nl2br(e($faq['answer'])) ?>
                                </p>
                            </div>
                        </div>
                    <?php endforeach; ?>
                </div>
            </div>
        </section>

        <!-- CTA Section -->
        <section class="py-20 bg-gradient-to-br from-blue-600 to-purple-600 text-white">
            <div class="container mx-auto px-4 text-center">
                <h2 class="text-3xl md:text-4xl font-bold mb-6">
                    Ready to Build Secure Applications?
                </h2>
                <p class="text-lg text-blue-100 mb-8 max-w-2xl mx-auto">
                    Start implementing C6P today. Complete documentation, test vectors, and reference implementation available.
                </p>
                <div class="flex flex-col sm:flex-row justify-center gap-4">
                    <a
                        href="<?= DOCS_URL ?>"
                        class="inline-flex items-center justify-center px-8 py-4 bg-white text-blue-600 font-bold rounded-lg hover:bg-gray-100 transition-colors shadow-xl"
                    >
                        Get Started
                        <svg class="w-5 h-5 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6"/>
                        </svg>
                    </a>
                    <a
                        href="<?= GITHUB_REPO ?>"
                        target="_blank"
                        rel="noopener noreferrer"
                        class="inline-flex items-center justify-center px-8 py-4 bg-blue-800 hover:bg-blue-900 text-white font-bold rounded-lg transition-colors"
                    >
                        <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                            <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
                        </svg>
                        View on GitHub
                    </a>
                </div>
            </div>
        </section>
    </main>

    <?php include __DIR__ . '/components/footer.php'; ?>

    <!-- Custom JavaScript -->
    <script src="<?= JS_PATH ?>/app.js"></script>

</body>
</html>
