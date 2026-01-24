<?php
$postNumber = $_POST_NUMBER ?? 3;
$randomId = $_RANDOM_ID ?? 'unknown';
$prettyUrl = $_PRETTY_URL ?? '';

// Load config for constants
require_once __DIR__ . '/includes/config.php';
require_once __DIR__ . '/includes/functions.php';
?>
<!DOCTYPE html>
<html lang="en" class="no-transition">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="ie=edge">

    <title>Metadata Minimization & The 63-Byte AAD Shield - C6P Protocol</title>
    <meta name="description" content="How C6P crushes the competition with best-in-class metadata privacy through sealed sender, 64KB padding, and cryptographic binding">

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
    <link rel="stylesheet" href="<?= CSS_PATH ?>/2ea637cbc609ca302e8fea25ba937e4f35796f846e6f140f16acaf178312e1e5ac48d6b262a0060dc927b2afff2ee60f42266fb6bb7c23202f65a9d9834ae55a.css">

    <!-- Alpine.js -->
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>

    <!-- Fonts -->
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
</head>
<body
    class="bg-white dark:bg-slate-900 text-gray-900 dark:text-white"
    x-data
    x-init="$store.app.init()"
    style="opacity: 0;"
>

    <?php include __DIR__ . '/components/header.php'; ?>

    <main>
        <!-- Hero Section with gradient -->
        <section class="relative py-24 overflow-hidden text-white">
            <!-- Dynamic background -->
            <div class="absolute inset-0 -z-10">
                <div class="absolute inset-0 bg-gradient-to-r from-indigo-900 via-purple-900 to-indigo-800 opacity-80 blur-3xl animate-lightwave mix-blend-overlay"></div>
                <div class="absolute inset-0 bg-gradient-to-tr from-purple-800 via-indigo-700 to-purple-900 opacity-60 blur-2xl animate-lightwave-delay mix-blend-overlay"></div>
                <div class="absolute inset-0 bg-black/20 animate-fade-slow"></div>
                <div class="absolute inset-0 bg-white/5 rounded-full blur-3xl animate-light-pulse"></div>
                <div class="absolute top-1/4 left-1/3 w-96 h-96 bg-purple-700/10 rounded-full blur-3xl animate-light-shift"></div>
                <div class="absolute bottom-1/3 right-1/4 w-72 h-72 bg-indigo-500/10 rounded-full blur-3xl animate-light-shift-delay"></div>
            </div>

            <div class="container mx-auto px-4 text-center relative z-10">
                <!-- Badge -->
                <div class="inline-flex items-center gap-2 px-4 py-2 bg-white/10 backdrop-blur-sm rounded-full text-sm font-semibold mb-6 border border-white/20">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>
                    </svg>
                    METADATA PRIVACY
                </div>

                <h1 class="text-4xl md:text-5xl font-extrabold mb-6 drop-shadow-lg">
                    Metadata Minimization & The AAD Shield
                </h1>

                <p class="text-lg md:text-xl text-purple-200 mb-10 max-w-3xl mx-auto drop-shadow-sm">
                    How C6P achieves best-in-class metadata privacy through sealed sender, fixed-size padding, and cryptographic binding that crushes the competition.
                </p>

                <!-- Stats Grid -->
                <div class="grid grid-cols-2 md:grid-cols-4 gap-4 max-w-3xl mx-auto mb-10">
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">63 Bytes</div>
                        <div class="text-sm text-purple-200">AAD Binding</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">64 KB</div>
                        <div class="text-sm text-purple-200">Fixed Padding</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">Hidden</div>
                        <div class="text-sm text-purple-200">Sender Always</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">5min</div>
                        <div class="text-sm text-purple-200">Time Rounding</div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 1: Privacy Philosophy -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        The Sharp Line: Content vs Metadata
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        C6P draws a sharp distinction between message content (fully E2E encrypted) and metadata (minimized by design).
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-white dark:bg-slate-900 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <p class="text-lg text-gray-600 dark:text-gray-400 mb-6 leading-relaxed">
                            While message content is protected by end-to-end encryption, <strong class="text-gray-900 dark:text-white">metadata</strong> can reveal who talks to whom, when, and how often. C6P minimizes metadata exposure through multiple layers of protection.
                        </p>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">What the Server Never Sees</h3>

                        <div class="grid md:grid-cols-2 gap-6 mb-8">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h4 class="font-bold text-gray-900 dark:text-white mb-2">Message Plaintext</h4>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Content is encrypted end-to-end with C6P session keys</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h4 class="font-bold text-gray-900 dark:text-white mb-2">Sender Identity</h4>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Sealed sender hides who sent the message (server only knows recipient)</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h4 class="font-bold text-gray-900 dark:text-white mb-2">Message Size</h4>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Fixed 64KB padding hides actual content length</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h4 class="font-bold text-gray-900 dark:text-white mb-2">Exact Timestamp</h4>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Timestamps rounded to nearest 5 minutes with random 0-5s jitter</p>
                                </div>
                            </div>
                        </div>

                        <!-- Design principle callout -->
                        <div class="bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-600 dark:border-blue-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-blue-900 dark:text-blue-100 mb-1">Design Philosophy</div>
                                    <p class="text-sm text-blue-800 dark:text-blue-200">
                                        C6P is designed with <strong>privacy by default</strong>, not privacy as an opt-in feature. Sealed sender with 64KB padding is STANDARD, not optional. This means every user benefits from best-in-class metadata privacy automatically.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 2: The 63-Byte AAD Shield -->
        <section class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        The 63-Byte AAD Shield
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Additional Authenticated Data (AAD) cryptographically binds all context to prevent tampering, splicing, and downgrade attacks.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-gray-50 dark:bg-slate-800 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">What is AAD?</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            AAD (Additional Authenticated Data) is metadata that's cryptographically authenticated but not encrypted. It ensures that envelope fields cannot be tampered with or reused in different contexts.
                        </p>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Canonical 63-Byte Layout</h3>

                        <!-- AAD anatomy -->
                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">AAD Construction (Exact 63 Bytes)</div>
                            <div class="text-gray-300 mb-1">1. <span class="text-yellow-400">"C6P_AAD_V1"</span> <span class="text-gray-500">(10 bytes)</span> ← Label</div>
                            <div class="text-gray-300 mb-1">2. <span class="text-blue-400">C6P_VERSION</span> <span class="text-gray-500">(1 byte = 0x01)</span> ← Protocol version</div>
                            <div class="text-gray-300 mb-1">3. <span class="text-blue-400">message_type</span> <span class="text-gray-500">(1 byte)</span> ← 0x01 dm, 0x02 group, etc.</div>
                            <div class="text-gray-300 mb-1">4. <span class="text-blue-400">stream_id</span> <span class="text-gray-500">(1 byte)</span> ← 0x01 i2r, 0x02 r2i</div>
                            <div class="text-gray-300 mb-1">5. <span class="text-blue-400">suite_id</span> <span class="text-gray-500">(1 byte)</span> ← 0x01 ChaCha20, 0x02 XChaCha20</div>
                            <div class="text-gray-300 mb-1">6. <span class="text-blue-400">aad_flags</span> <span class="text-gray-500">(1 byte = 0x00)</span> ← Reserved for future</div>
                            <div class="text-gray-300 mb-1">7. <span class="text-purple-400">session_id</span> <span class="text-gray-500">(8 bytes)</span> ← Session identifier</div>
                            <div class="text-gray-300 mb-1">8. <span class="text-green-400">session_binding</span> <span class="text-gray-500">(32 bytes)</span> ← Device pair SHA-256</div>
                            <div class="text-gray-300 mb-3">9. <span class="text-orange-400">BE64(counter)</span> <span class="text-gray-500">(8 bytes)</span> ← Message counter</div>
                            <div class="text-gray-500 border-t border-gray-700 pt-2">Total: 10 + 5 + 8 + 32 + 8 = <span class="text-yellow-400 font-bold">63 bytes</span></div>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Security Properties</h3>

                        <!-- Security properties grid -->
                        <div class="grid md:grid-cols-2 gap-4 mb-6">
                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-purple-600 dark:text-purple-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Downgrade Prevention</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Protocol version and suite bound in AAD — tampering fails AEAD verification</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Splicing Resistance</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Session binding prevents messages from being moved between sessions</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-green-600 dark:text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Replay Detection</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Counter in AAD ensures duplicate messages are rejected even if AEAD verifies</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Type Confusion</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Message type bound — DM cannot be relabeled as group message</p>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <!-- Critical requirement -->
                        <div class="bg-red-50 dark:bg-red-900/20 border-l-4 border-red-600 dark:border-red-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-red-900 dark:text-red-100 mb-1">Normative Requirement</div>
                                    <p class="text-sm text-red-800 dark:text-red-200">
                                        AAD MUST be exactly 63 bytes in C6P v1. Any other length is an implementation bug and MUST cause fail-closed rejection. This is non-negotiable for security.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 3: Session Binding -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Session Binding: Device Pair Lockdown
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Every message is cryptographically bound to the exact device pair that established the session.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-white dark:bg-slate-900 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Why Session Binding?</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            Without session binding, a malicious server could splice messages between different sessions or device pairs. Session binding prevents this by creating a unique fingerprint for each device pair.
                        </p>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Computation</h3>

                        <!-- Session binding formula -->
                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Session Binding Derivation</div>
                            <pre class="text-gray-300"><code>session_binding = SHA-256(
    "C6P_BIND_V1" ||
    session_id(8 bytes) ||
    initiator_device_id(16 bytes) ||
    responder_device_id(16 bytes)
)

// Output: 32 bytes (256 bits)
// Included in every AAD construction</code></pre>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Attack Scenarios Prevented</h3>

                        <!-- Attack scenarios -->
                        <div class="space-y-4 mb-6">
                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                                    </svg>
                                    <div class="flex-1">
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Cross-Session Splicing</div>
                                        <p class="text-sm text-gray-600 dark:text-gray-400 mb-2">
                                            <strong>Attack:</strong> Malicious server copies message from Session A to Session B
                                        </p>
                                        <p class="text-sm text-green-700 dark:text-green-400">
                                            <strong>Defense:</strong> Different session_id means different session_binding → AEAD verification fails
                                        </p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                                    </svg>
                                    <div class="flex-1">
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Device Confusion</div>
                                        <p class="text-sm text-gray-600 dark:text-gray-400 mb-2">
                                            <strong>Attack:</strong> Server delivers message intended for Device A to Device B
                                        </p>
                                        <p class="text-sm text-green-700 dark:text-green-400">
                                            <strong>Defense:</strong> Wrong device_id means wrong session_binding → AEAD verification fails
                                        </p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                                    </svg>
                                    <div class="flex-1">
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Man-in-the-Middle</div>
                                        <p class="text-sm text-gray-600 dark:text-gray-400 mb-2">
                                            <strong>Attack:</strong> Attacker intercepts and modifies AAD fields (suite, type, etc.)
                                        </p>
                                        <p class="text-sm text-green-700 dark:text-green-400">
                                            <strong>Defense:</strong> Any AAD modification breaks AEAD authentication → rejection
                                        </p>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <!-- Security note -->
                        <div class="bg-green-50 dark:bg-green-900/20 border-l-4 border-green-600 dark:border-green-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-green-600 dark:text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-green-900 dark:text-green-100 mb-1">Cryptographic Guarantee</div>
                                    <p class="text-sm text-green-800 dark:text-green-200">
                                        Session binding is computed from <strong>canonical, locally trusted session state</strong>, not from attacker-controlled fields. The server cannot "fix" AAD to match a spliced message because it doesn't know the session keys.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 4: Sealed Sender & Padding -->
        <section class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Sealed Sender: Server Blindness
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        The server routes messages without knowing who sent them, protecting your social graph.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-gray-50 dark:bg-slate-800 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">How Sealed Sender Works</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            Messages use a two-layer envelope structure: an outer envelope for server routing (recipient only) and an encrypted inner envelope containing sender identity.
                        </p>

                        <!-- Envelope structure -->
                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Two-Layer Envelope Structure</div>
                            <div class="text-yellow-400 mb-2">┌─ Outer Envelope (Server Sees) ─────────────┐</div>
                            <div class="text-blue-400 ml-4 mb-1">│ to_user_id: UUID (routing only)</div>
                            <div class="text-blue-400 ml-4 mb-1">│ message_type: "sealed_sender"</div>
                            <div class="text-blue-400 ml-4 mb-1">│ created_at: 2026-01-20T12:30:00Z (rounded)</div>
                            <div class="text-blue-400 ml-4 mb-2">│ encrypted_envelope: 64KB (PADDED)</div>
                            <div class="text-yellow-400 mb-3">└────────────────────────────────────────────┘</div>

                            <div class="text-green-400 mb-2">   ┌─ Inner Envelope (Recipient Decrypts) ──┐</div>
                            <div class="text-purple-400 ml-4 mb-1">   │ from_user_id: UUID (HIDDEN)</div>
                            <div class="text-purple-400 ml-4 mb-1">   │ from_convro_number: "+99 123 456"</div>
                            <div class="text-purple-400 ml-4 mb-1">   │ session_id: BYTEA</div>
                            <div class="text-purple-400 ml-4 mb-1">   │ actual_message_type: "encrypted_message"</div>
                            <div class="text-purple-400 ml-4 mb-1">   │ actual_created_at: (precise timestamp)</div>
                            <div class="text-purple-400 ml-4 mb-1">   │ encrypted_blob: C6P payload</div>
                            <div class="text-green-400 ml-4">   └────────────────────────────────────────┘</div>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Fixed 64KB Padding</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            All sealed messages are padded to exactly 64KB (65,536 bytes). This hides the actual message length from the server.
                        </p>

                        <!-- Padding benefits -->
                        <div class="grid md:grid-cols-3 gap-4 mb-6">
                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="text-2xl font-bold text-purple-600 dark:text-purple-400 mb-2">64 KB</div>
                                <div class="text-sm font-semibold text-gray-900 dark:text-white mb-1">Fixed Size</div>
                                <p class="text-xs text-gray-600 dark:text-gray-400">Every message exactly same size — no length analysis</p>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="text-2xl font-bold text-blue-600 dark:text-blue-400 mb-2">5 min</div>
                                <div class="text-sm font-semibold text-gray-900 dark:text-white mb-1">Time Rounding</div>
                                <p class="text-xs text-gray-600 dark:text-gray-400">Timestamps rounded to nearest 5 minutes</p>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="text-2xl font-bold text-green-600 dark:text-green-400 mb-2">0-5s</div>
                                <div class="text-sm font-semibold text-gray-900 dark:text-white mb-1">Random Jitter</div>
                                <p class="text-xs text-gray-600 dark:text-gray-400">Delivery delay prevents correlation</p>
                            </div>
                        </div>

                        <!-- Standard vs sealed comparison -->
                        <div class="overflow-x-auto rounded-xl border border-gray-200 dark:border-gray-700">
                            <table class="w-full">
                                <thead class="bg-gray-100 dark:bg-slate-950">
                                    <tr>
                                        <th class="px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-white">Mode</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-white">Server Sees Sender</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-white">Message Size</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-white">Timestamp</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                                    <tr class="bg-white dark:bg-slate-900">
                                        <td class="px-6 py-4 font-mono text-sm text-gray-600 dark:text-gray-400">Standard</td>
                                        <td class="px-6 py-4 text-sm">
                                            <span class="inline-flex items-center gap-1 text-red-600 dark:text-red-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                                </svg>
                                                Visible
                                            </span>
                                        </td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Variable (~2-10 KB)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Precise</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900">
                                        <td class="px-6 py-4 font-mono text-sm font-bold text-purple-600 dark:text-purple-400">Sealed</td>
                                        <td class="px-6 py-4 text-sm">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                                </svg>
                                                Hidden
                                            </span>
                                        </td>
                                        <td class="px-6 py-4 text-sm font-bold text-gray-900 dark:text-white">Fixed 64 KB ALWAYS</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Rounded (±5 min)</td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 5: Privacy Comparison -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        How C6P Crushes the Competition
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Side-by-side comparison shows C6P provides best-in-class metadata privacy by default.
                    </p>
                </div>

                <div class="max-w-6xl mx-auto">
                    <!-- Comparison table -->
                    <div class="bg-white dark:bg-slate-900 rounded-xl overflow-hidden border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <div class="overflow-x-auto">
                            <table class="w-full">
                                <thead class="bg-gradient-to-r from-purple-600 to-indigo-600 text-white">
                                    <tr>
                                        <th class="px-6 py-4 text-left text-sm font-bold">Metadata Type</th>
                                        <th class="px-6 py-4 text-left text-sm font-bold">WhatsApp</th>
                                        <th class="px-6 py-4 text-left text-sm font-bold">Signal<br/>(Standard)</th>
                                        <th class="px-6 py-4 text-left text-sm font-bold">Signal<br/>(Sealed)</th>
                                        <th class="px-6 py-4 text-left text-sm font-bold bg-purple-700">Convro<br/>(STANDARD)</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                                    <tr class="hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-semibold text-gray-900 dark:text-white">Sender identity</td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                                </svg>
                                                Visible
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                                </svg>
                                                Visible
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-red-600 dark:text-red-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                                </svg>
                                                Hidden
                                            </span>
                                        </td>
                                        <td class="px-6 py-4 bg-purple-50 dark:bg-purple-900/20">
                                            <span class="inline-flex items-center gap-1 text-red-600 dark:text-red-400 font-bold">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                                </svg>
                                                Hidden (ALWAYS)
                                            </span>
                                        </td>
                                    </tr>
                                    <tr class="hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-semibold text-gray-900 dark:text-white">Recipient identity</td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                                </svg>
                                                Visible
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                                </svg>
                                                Visible
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                                </svg>
                                                Visible
                                            </span>
                                        </td>
                                        <td class="px-6 py-4 bg-purple-50 dark:bg-purple-900/20">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                                </svg>
                                                Visible
                                            </span>
                                        </td>
                                    </tr>
                                    <tr class="hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-semibold text-gray-900 dark:text-white">Message content</td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-red-600 dark:text-red-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                                </svg>
                                                Encrypted
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-red-600 dark:text-red-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                                </svg>
                                                Encrypted
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-red-600 dark:text-red-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                                </svg>
                                                Encrypted
                                            </span>
                                        </td>
                                        <td class="px-6 py-4 bg-purple-50 dark:bg-purple-900/20">
                                            <span class="inline-flex items-center gap-1 text-red-600 dark:text-red-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                                </svg>
                                                Encrypted (C6P)
                                            </span>
                                        </td>
                                    </tr>
                                    <tr class="hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-semibold text-gray-900 dark:text-white">Message size</td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-yellow-600 dark:text-yellow-400">
                                                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                                                    <circle cx="12" cy="12" r="10"/>
                                                </svg>
                                                Variable
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-yellow-600 dark:text-yellow-400">
                                                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                                                    <circle cx="12" cy="12" r="10"/>
                                                </svg>
                                                Variable
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-yellow-600 dark:text-yellow-400">
                                                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                                                    <circle cx="12" cy="12" r="10"/>
                                                </svg>
                                                Padded
                                            </span>
                                        </td>
                                        <td class="px-6 py-4 bg-purple-50 dark:bg-purple-900/20">
                                            <span class="inline-flex items-center gap-1 text-red-600 dark:text-red-400 font-bold">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                                </svg>
                                                Fixed 64KB (ALWAYS)
                                            </span>
                                        </td>
                                    </tr>
                                    <tr class="hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-semibold text-gray-900 dark:text-white">Exact timestamp</td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                                </svg>
                                                Precise
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                                </svg>
                                                Precise
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                                </svg>
                                                Precise
                                            </span>
                                        </td>
                                        <td class="px-6 py-4 bg-purple-50 dark:bg-purple-900/20">
                                            <span class="inline-flex items-center gap-1 text-yellow-600 dark:text-yellow-400 font-bold">
                                                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                                                    <circle cx="12" cy="12" r="10"/>
                                                </svg>
                                                5min rounded (ALWAYS)
                                            </span>
                                        </td>
                                    </tr>
                                    <tr class="hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-semibold text-gray-900 dark:text-white">Social graph</td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-red-700 dark:text-red-500">
                                                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                                                    <circle cx="12" cy="12" r="10"/>
                                                </svg>
                                                Full exposure
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-red-700 dark:text-red-500">
                                                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                                                    <circle cx="12" cy="12" r="10"/>
                                                </svg>
                                                Full exposure
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400">
                                                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                                                    <circle cx="12" cy="12" r="10"/>
                                                </svg>
                                                Recipient-only
                                            </span>
                                        </td>
                                        <td class="px-6 py-4 bg-purple-50 dark:bg-purple-900/20">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400 font-bold">
                                                <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                                                    <circle cx="12" cy="12" r="10"/>
                                                </svg>
                                                Recipient-only (ALWAYS)
                                            </span>
                                        </td>
                                    </tr>
                                    <tr class="hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-semibold text-gray-900 dark:text-white">Timing jitter</td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-red-600 dark:text-red-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                                </svg>
                                                None
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-red-600 dark:text-red-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                                </svg>
                                                None
                                            </span>
                                        </td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center gap-1 text-red-600 dark:text-red-400">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                                </svg>
                                                None
                                            </span>
                                        </td>
                                        <td class="px-6 py-4 bg-purple-50 dark:bg-purple-900/20">
                                            <span class="inline-flex items-center gap-1 text-green-600 dark:text-green-400 font-bold">
                                                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                                </svg>
                                                0-5s random delay
                                            </span>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>
                    </div>

                    <!-- Winner callout -->
                    <div class="bg-gradient-to-r from-purple-600 to-indigo-600 rounded-xl p-8 text-white text-center">
                        <div class="text-4xl font-bold mb-4">🏆 Convro = Best-in-class privacy by default!</div>
                        <div class="grid md:grid-cols-3 gap-4 mt-6">
                            <div class="bg-white/10 backdrop-blur-sm rounded-lg p-4">
                                <div class="font-bold mb-1">WhatsApp</div>
                                <p class="text-sm text-purple-200">Poor privacy (server sees everything)</p>
                            </div>
                            <div class="bg-white/10 backdrop-blur-sm rounded-lg p-4">
                                <div class="font-bold mb-1">Signal standard</div>
                                <p class="text-sm text-purple-200">Good E2E, but server sees social graph</p>
                            </div>
                            <div class="bg-white/10 backdrop-blur-sm rounded-lg p-4">
                                <div class="font-bold mb-1">Signal sealed</div>
                                <p class="text-sm text-purple-200">Optional privacy enhancement</p>
                            </div>
                        </div>
                        <div class="mt-6 text-xl font-bold">
                            ⚡ <strong>Convro:</strong> Sealed sender is STANDARD (not optional) + 64KB padding + timing jitter
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Key Takeaways -->
        <section class="relative py-24 overflow-hidden text-white">
            <div class="absolute inset-0 -z-10">
                <div class="absolute inset-0 bg-gradient-to-r from-indigo-900 via-purple-900 to-indigo-800 opacity-80 blur-3xl animate-lightwave mix-blend-overlay"></div>
                <div class="absolute inset-0 bg-gradient-to-tr from-purple-800 via-indigo-700 to-purple-900 opacity-60 blur-2xl animate-lightwave-delay mix-blend-overlay"></div>
            </div>

            <div class="container mx-auto px-4 relative z-10">
                <div class="max-w-4xl mx-auto">
                    <h2 class="text-3xl md:text-4xl font-bold text-center mb-12">Key Takeaways</h2>

                    <div class="grid md:grid-cols-2 gap-6">
                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>63-byte AAD</strong> cryptographically binds all context to prevent tampering and splicing</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Session binding</strong> locks messages to exact device pair, preventing cross-session attacks</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Sealed sender ALWAYS</strong> — server never knows who sent a message (privacy by default)</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>64KB fixed padding</strong> hides message length from traffic analysis attacks</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Timestamp rounding + jitter</strong> prevents precise timing correlation (5min ± 0-5s)</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Best-in-class privacy</strong> — C6P crushes WhatsApp and equals/exceeds Signal's sealed mode</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

    </main>

    <?php include __DIR__ . '/components/footer.php'; ?>

    <!-- Custom JavaScript -->
    <script src="<?= JS_PATH ?>/app.js"></script>

</body>
</html>
