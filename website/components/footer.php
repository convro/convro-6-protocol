<footer class="bg-gray-50 dark:bg-slate-900 border-t border-gray-200 dark:border-gray-800 py-12 md:py-16">
    <div class="container mx-auto px-4">
        <div class="grid md:grid-cols-2 lg:grid-cols-4 gap-8 mb-12">
            <!-- Brand -->
            <div>
                <div class="flex items-center gap-2 mb-4">
                    <img src="<?= LOGO_ICON_SQUARE ?>" alt="Convro" class="h-8 w-8">
                    <span class="font-bold text-lg text-gray-900 dark:text-white">
                        Convro 6 Protocol
                    </span>
                </div>
                <p class="text-sm text-gray-600 dark:text-gray-400 mb-4">
                    Production-ready E2E encryption protocol. Audit-grade security for messaging applications.
                </p>
                <div class="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
                    <span class="inline-flex items-center gap-1 px-2 py-1 bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200 rounded-full">
                        <span class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
                        Production Ready
                    </span>
                </div>
            </div>

            <!-- Protocol -->
            <div>
                <h3 class="font-semibold text-gray-900 dark:text-white mb-4">Protocol</h3>
                <ul class="space-y-2 text-sm">
                    <li>
                        <a href="<?= DOCS_URL ?>/crypto" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            Crypto Specification
                        </a>
                    </li>
                    <li>
                        <a href="<?= DOCS_URL ?>/handshake" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            IslandAccord Handshake
                        </a>
                    </li>
                    <li>
                        <a href="<?= DOCS_URL ?>/identity" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            Identity Management
                        </a>
                    </li>
                    <li>
                        <a href="<?= DOCS_URL ?>/Sessions" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            Session Ratcheting
                        </a>
                    </li>
                </ul>
            </div>

            <!-- Resources -->
            <div>
                <h3 class="font-semibold text-gray-900 dark:text-white mb-4">Resources</h3>
                <ul class="space-y-2 text-sm">
                    <li>
                        <a href="<?= THREAT_MODEL_PDF ?>" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            Threat Model (PDF)
                        </a>
                    </li>
                    <li>
                        <a href="<?= TEST_VECTORS_URL ?>" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            Test Vectors
                        </a>
                    </li>
                    <li>
                        <a href="<?= API_DOCS_URL ?>" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            API Documentation
                        </a>
                    </li>
                    <li>
                        <a href="<?= GITHUB_REPO ?>" target="_blank" rel="noopener noreferrer" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            GitHub Repository
                            <svg class="inline w-3 h-3 ml-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/>
                            </svg>
                        </a>
                    </li>
                </ul>
            </div>

            <!-- Security & Community -->
            <div>
                <h3 class="font-semibold text-gray-900 dark:text-white mb-4">Security</h3>
                <ul class="space-y-2 text-sm mb-6">
                    <li>
                        <a href="mailto:<?= SECURITY_EMAIL ?>" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            Report Vulnerability
                        </a>
                    </li>
                    <li>
                        <span class="text-gray-600 dark:text-gray-400">
                            <?= SECURITY_EMAIL ?>
                        </span>
                    </li>
                    <li>
                        <a href="#" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            PGP Key (TBD)
                        </a>
                    </li>
                </ul>

                <h3 class="font-semibold text-gray-900 dark:text-white mb-4">Community</h3>
                <ul class="space-y-2 text-sm">
                    <li>
                        <a href="<?= DISCORD_URL ?>" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            Discord (TBD)
                        </a>
                    </li>
                    <li>
                        <a href="<?= TWITTER_URL ?>" class="text-gray-600 dark:text-gray-400 hover:text-blue-600 dark:hover:text-blue-400 transition-colors">
                            Twitter (TBD)
                        </a>
                    </li>
                </ul>
            </div>
        </div>

        <!-- Bottom Bar -->
        <div class="pt-8 border-t border-gray-200 dark:border-gray-800">
            <div class="flex flex-col md:flex-row justify-between items-center gap-4">
                <!-- Copyright -->
                <div class="text-sm text-gray-500 dark:text-gray-400">
                    © <?= date('Y') ?> Convro Team • Dual Licensed:
                    <a href="<?= GITHUB_REPO ?>/blob/main/LICENSE-APACHE" class="hover:text-blue-600 dark:hover:text-blue-400 transition-colors">Apache 2.0</a>
                    /
                    <a href="<?= GITHUB_REPO ?>/blob/main/LICENSE-MIT" class="hover:text-blue-600 dark:hover:text-blue-400 transition-colors">MIT</a>
                </div>

                <!-- Tech Stack Badge -->
                <div class="flex items-center gap-4 text-sm text-gray-500 dark:text-gray-400">
                    <span class="flex items-center gap-1">
                        Built with
                        <span class="text-orange-600 dark:text-orange-400 font-mono">Rust</span>
                        🦀
                    </span>
                    <span class="hidden md:inline">•</span>
                    <span class="font-mono">MSRV <?= MSRV ?></span>
                </div>
            </div>
        </div>
    </div>
</footer>
