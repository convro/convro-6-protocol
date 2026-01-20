<?php
$postNumber = $_POST_NUMBER ?? 1;
$randomId = $_RANDOM_ID ?? 'unknown';
$prettyUrl = $_PRETTY_URL ?? '';

// Load config for constants
require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../includes/functions.php';
?>
<!DOCTYPE html>
<html lang="en" class="no-transition">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="ie=edge">

    <title>Forward Secrecy & Cryptographic Foundation - C6P Protocol</title>
    <meta name="description" content="How C6P v1 ensures forward secrecy through per-message key derivation, symmetric ratcheting, and production-grade AEAD with fail-closed design">

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

    <?php include __DIR__ . '/../components/header.php'; ?>

    <main>
        <!-- Hero Section -->
        <section class="relative py-24 overflow-hidden text-white">
            <div class="absolute inset-0 -z-10">
                <div class="absolute inset-0 bg-gradient-to-r from-indigo-900 via-purple-900 to-indigo-800 opacity-80 blur-3xl animate-lightwave mix-blend-overlay"></div>
                <div class="absolute inset-0 bg-gradient-to-tr from-purple-800 via-indigo-700 to-purple-900 opacity-60 blur-2xl animate-lightwave-delay mix-blend-overlay"></div>
                <div class="absolute inset-0 bg-black/20 animate-fade-slow"></div>
                <div class="absolute inset-0 bg-white/5 rounded-full blur-3xl animate-light-pulse"></div>
                <div class="absolute top-1/4 left-1/3 w-96 h-96 bg-purple-700/10 rounded-full blur-3xl animate-light-shift"></div>
                <div class="absolute bottom-1/3 right-1/4 w-72 h-72 bg-indigo-500/10 rounded-full blur-3xl animate-light-shift-delay"></div>
            </div>

            <div class="container mx-auto px-4 text-center relative z-10">
                <div class="inline-flex items-center gap-2 px-4 py-2 bg-white/10 backdrop-blur-sm rounded-full text-sm font-semibold mb-6 border border-white/20">
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>
                    </svg>
                    CRYPTOGRAPHIC FOUNDATION
                </div>

                <h1 class="text-4xl md:text-5xl font-extrabold mb-6 drop-shadow-lg">
                    Forward Secrecy & Cryptographic Foundation
                </h1>

                <p class="text-lg md:text-xl text-purple-200 mb-10 max-w-3xl mx-auto drop-shadow-sm">
                    How C6P v1 ensures that compromising current cryptographic state cannot reveal past messages through per-message key derivation, symmetric ratcheting, and production-grade AEAD.
                </p>

                <div class="grid grid-cols-2 md:grid-cols-4 gap-4 max-w-3xl mx-auto mb-10">
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">ChaCha20</div>
                        <div class="text-sm text-purple-200">Production AEAD</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">256-bit</div>
                        <div class="text-sm text-purple-200">Keys</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">Per-Msg</div>
                        <div class="text-sm text-purple-200">Ephemeral</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">Fail-Closed</div>
                        <div class="text-sm text-purple-200">By Design</div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 1: Forward Secrecy -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        What is Forward Secrecy?
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Protection against past message compromise, even when current state is breached.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-white dark:bg-slate-900 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <p class="text-lg text-gray-600 dark:text-gray-400 mb-6 leading-relaxed">
                            <strong class="text-gray-900 dark:text-white">Forward secrecy</strong> (also called "perfect forward secrecy") is a property of secure communication protocols where the compromise of long-term keys does not compromise past session keys. In the context of C6P v1, this means:
                        </p>

                        <div class="grid md:grid-cols-2 gap-6 mb-8">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h3 class="font-bold text-gray-900 dark:text-white mb-2">Unique Ephemeral Keys</h3>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Each message uses a unique ephemeral key derived from a chain key that's never transmitted</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h3 class="font-bold text-gray-900 dark:text-white mb-2">Immediate Key Deletion</h3>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Keys are deleted immediately after use — there's no way to recover them</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h3 class="font-bold text-gray-900 dark:text-white mb-2">Future-Only Compromise</h3>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Compromise of current state reveals only future messages, not past ones</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h3 class="font-bold text-gray-900 dark:text-white mb-2">Device Seizure Protection</h3>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Even if an attacker gains access to your device today, they cannot decrypt messages sent yesterday</p>
                                </div>
                            </div>
                        </div>

                        <div class="bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-600 dark:border-blue-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-blue-900 dark:text-blue-100 mb-1">Real-World Impact</div>
                                    <p class="text-sm text-blue-800 dark:text-blue-200">
                                        If your phone is seized by law enforcement or compromised by malware, past conversations remain secure. The attacker can only read new messages going forward, assuming the compromise persists.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 2: Symmetric Ratchet -->
        <section class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        The Symmetric Ratchet Mechanism
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        One-way chain key advancement that never allows backward computation.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-gray-50 dark:bg-slate-800 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <p class="text-lg text-gray-600 dark:text-gray-400 mb-6 leading-relaxed">
                            C6P v1 implements a <strong class="text-gray-900 dark:text-white">symmetric ratchet</strong> (also called a "hash ratchet") that advances forward with each message. Unlike asymmetric ratchets (like in Signal's Double Ratchet), this ratchet doesn't require new Diffie-Hellman exchanges per message.
                        </p>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">How It Works: The Chain Key Dance</h3>

                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-blue-400 mb-1">1. Start with Initial Chain Key (CK₀)</div>
                            <div class="text-gray-500 ml-4 mb-1">↓ HKDF-Extract + HKDF-Expand</div>
                            <div class="text-blue-400 mb-1">2. Derive Message Key (MK₁) for counter=1</div>
                            <div class="text-gray-500 ml-4 mb-1">↓ Encrypt message</div>
                            <div class="text-blue-400 mb-1">3. Derive Next Chain Key (CK₁) from same PRK</div>
                            <div class="text-gray-500 ml-4 mb-1">↓ Delete CK₀ and MK₁ immediately</div>
                            <div class="text-blue-400 mb-1">4. CK₁ becomes new base for counter=2</div>
                            <div class="text-gray-500 ml-4">↓ Repeat forever...</div>
                        </div>

                        <div class="bg-red-50 dark:bg-red-900/20 border-l-4 border-red-600 dark:border-red-400 rounded-lg p-6 mb-8">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-red-900 dark:text-red-100 mb-1">Critical Security Property</div>
                                    <p class="text-sm text-red-800 dark:text-red-200">
                                        The chain key derivation is <strong>one-way</strong>. Given CK₁₀, you cannot compute CK₉. This ensures that compromising the current state doesn't reveal past keys. The ratchet only moves forward, never backward.
                                    </p>
                                </div>
                            </div>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Per-Stream State Management</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-4">
                            Each C6P session maintains <strong class="text-gray-900 dark:text-white">two independent ratchets</strong>:
                        </p>

                        <div class="overflow-x-auto rounded-xl border border-gray-200 dark:border-gray-700">
                            <table class="w-full">
                                <thead class="bg-gray-800 dark:bg-slate-950 text-white">
                                    <tr>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Stream</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Direction</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Purpose</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">i2r (0x01)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Initiator → Responder</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Initiator sends, responder receives</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">r2i (0x02)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Responder → Initiator</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Responder sends, initiator receives</td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 3: Key Derivation -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Cryptographic Key Derivation
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        HKDF-based derivation with domain-separated labels for security.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-white dark:bg-slate-900 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover">
                        <p class="text-lg text-gray-600 dark:text-gray-400 mb-6 leading-relaxed">
                            Every message key is derived through a carefully designed process using <strong class="text-gray-900 dark:text-white">HKDF</strong> (HMAC-based Key Derivation Function) with domain-separated labels to prevent key reuse across different contexts.
                        </p>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">The Derivation Process</h3>

                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3 font-mono">Normative Key Derivation (from c6p-key-schedule.md §6)</div>
                            <pre class="font-mono text-sm text-gray-300"><code>// Step 1: Create message-specific salt
salt_msg = SHA256("C6P_MSG_V1" || CTX || transcript_hash ||
                   STREAM_CTX || BE64(counter))

// Step 2: Extract pseudorandom key from chain key
prk_msg = HKDF-Extract(salt=salt_msg, ikm=CK)

// Step 3: Expand to message key material
mk_material = HKDF-Expand(prk_msg,
                          info="C6P_MSG_V1" || U8(0x01) || STREAM_CTX,
                          L=32)

// Step 4: Map to cipher suite key
suite_key = map_to_suite_key(mk_material, suite_id)

// Step 5: Derive deterministic nonce
nonce = derive_nonce(mk_material, counter, suite_id, session_binding)

// Step 6: Derive next chain key (from same prk_msg)
CK_next = HKDF-Expand(prk_msg,
                      info="C6P_CHAIN_V1" || U8(0x01) || STREAM_CTX || BE64(counter),
                      L=32)</code></pre>
                        </div>

                        <div class="bg-yellow-50 dark:bg-yellow-900/20 border-l-4 border-yellow-600 dark:border-yellow-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-yellow-600 dark:text-yellow-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-yellow-900 dark:text-yellow-100 mb-1">Domain Separation</div>
                                    <p class="text-sm text-yellow-800 dark:text-yellow-200">
                                        The labels <code class="font-mono bg-yellow-100 dark:bg-yellow-900/40 px-1 py-0.5 rounded text-xs">"C6P_MSG_V1"</code> and <code class="font-mono bg-yellow-100 dark:bg-yellow-900/40 px-1 py-0.5 rounded text-xs">"C6P_CHAIN_V1"</code> are <strong>normative</strong>. Custom labels break interoperability and security guarantees.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 4: AEAD Cipher Suites -->
        <section class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        AEAD Cipher Suites
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Production-grade Authenticated Encryption with Associated Data for message protection.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-gray-50 dark:bg-slate-800 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">ChaCha20-Poly1305: Production Default</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            C6P v1 uses <strong class="text-gray-900 dark:text-white">ChaCha20-Poly1305</strong> as the default and required AEAD cipher. This is a modern, high-performance authenticated encryption algorithm that's battle-tested and widely deployed.
                        </p>

                        <div class="overflow-x-auto rounded-xl border border-gray-200 dark:border-gray-700 mb-6">
                            <table class="w-full">
                                <thead class="bg-gray-800 dark:bg-slate-950 text-white">
                                    <tr>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Suite</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Suite ID</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Key</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Nonce</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Tag</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Status</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-semibold text-gray-900 dark:text-white">ChaCha20-Poly1305</td>
                                        <td class="px-6 py-4 font-mono text-sm text-green-700 dark:text-green-400">0x01</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">32 bytes</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">12 bytes</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">16 bytes</td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center px-2 py-1 text-xs font-semibold rounded-full bg-green-100 dark:bg-green-900/40 text-green-800 dark:text-green-200">
                                                REQUIRED
                                            </span>
                                        </td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 text-gray-600 dark:text-gray-400">XChaCha20-Poly1305</td>
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">0x02</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">32 bytes</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">24 bytes</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">16 bytes</td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center px-2 py-1 text-xs font-semibold rounded-full bg-blue-100 dark:bg-blue-900/40 text-blue-800 dark:text-blue-200">
                                                OPTIONAL
                                            </span>
                                        </td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 text-gray-600 dark:text-gray-400">AEGIS-128L</td>
                                        <td class="px-6 py-4 font-mono text-sm text-purple-600 dark:text-purple-400">0x03</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">16 bytes</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">16 bytes</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">16 bytes</td>
                                        <td class="px-6 py-4">
                                            <span class="inline-flex items-center px-2 py-1 text-xs font-semibold rounded-full bg-orange-100 dark:bg-orange-900/40 text-orange-800 dark:text-orange-200">
                                                GATED
                                            </span>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Why ChaCha20-Poly1305?</h3>

                        <div class="grid md:grid-cols-2 gap-4 mb-6">
                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-green-600 dark:text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">High Performance</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Optimized for modern CPUs without AES-NI — faster on mobile devices</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Battle-Tested</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Used by TLS 1.3, WireGuard, Signal — proven in production</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-purple-600 dark:text-purple-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Constant-Time</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Resistant to timing attacks — no secret-dependent branches</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-orange-600 dark:text-orange-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 21a4 4 0 01-4-4V5a2 2 0 012-2h4a2 2 0 012 2v12a4 4 0 01-4 4zm0 0h12a2 2 0 002-2v-4a2 2 0 00-2-2h-2.343M11 7.343l1.657-1.657a2 2 0 012.828 0l2.829 2.829a2 2 0 010 2.828l-8.486 8.485M7 17h.01"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Simple Design</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Easy to implement correctly — fewer opportunities for bugs</p>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div class="bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-600 dark:border-blue-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-blue-900 dark:text-blue-100 mb-1">Optional Suites</div>
                                    <p class="text-sm text-blue-800 dark:text-blue-200">
                                        XChaCha20-Poly1305 (extended 24-byte nonce) and AEGIS-128L (high-performance hardware-accelerated) are optional in v1. All implementations MUST support ChaCha20-Poly1305 (0x01).
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 5: Nonce Derivation -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Deterministic Nonce Derivation
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Safe by construction — no randomness needed, no nonce reuse possible.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-white dark:bg-slate-900 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Why Deterministic Nonces Are Safe</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            C6P uses <strong class="text-gray-900 dark:text-white">deterministic nonces</strong> — derived from message context, not random. This is safe because:
                        </p>

                        <div class="space-y-4 mb-6">
                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <div class="bg-green-600 text-white rounded-full w-8 h-8 flex items-center justify-center flex-shrink-0 font-bold">1</div>
                                    <div class="flex-1">
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Per-Message Keys</div>
                                        <p class="text-sm text-gray-600 dark:text-gray-400">
                                            Every message uses a unique AEAD key derived from <code class="font-mono bg-gray-100 dark:bg-slate-700 px-1 py-0.5 rounded text-xs">(session, stream, counter, type, suite)</code>
                                        </p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <div class="bg-blue-600 text-white rounded-full w-8 h-8 flex items-center justify-center flex-shrink-0 font-bold">2</div>
                                    <div class="flex-1">
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Context-Bound Derivation</div>
                                        <p class="text-sm text-gray-600 dark:text-gray-400">
                                            Nonce binds to all message context — replay detection prevents duplicate counters
                                        </p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <div class="bg-purple-600 text-white rounded-full w-8 h-8 flex items-center justify-center flex-shrink-0 font-bold">3</div>
                                    <div class="flex-1">
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Explicit Replay Rejection</div>
                                        <p class="text-sm text-gray-600 dark:text-gray-400">
                                            Even if AEAD verifies, duplicate <code class="font-mono bg-gray-100 dark:bg-slate-700 px-1 py-0.5 rounded text-xs">(session, stream, counter)</code> is rejected
                                        </p>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Canonical Nonce Construction</h3>

                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Deterministic Nonce Derivation</div>
                            <pre class="text-gray-300"><code>// Step 1: PRK from session binding + message key material
prk_nonce = HKDF-Extract(
    salt = session_binding,
    ikm = mk_material
)

// Step 2: Info binding all message context
info = "C6P_NONCE_V1" ||
       U8(C6P_VERSION) ||
       U8(suite_id) ||
       U8(message_type) ||
       U8(stream_id) ||
       session_id(8) ||
       BE64(counter)

// Step 3: Expand to suite-specific nonce length
nonce = HKDF-Expand(prk_nonce, info, L=nonce_len)

// Nonce lengths per suite:
// ChaCha20-Poly1305:   12 bytes
// XChaCha20-Poly1305:  24 bytes
// AEGIS-128L:          16 bytes</code></pre>
                        </div>

                        <div class="bg-green-50 dark:bg-green-900/20 border-l-4 border-green-600 dark:border-green-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-green-600 dark:text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-green-900 dark:text-green-100 mb-1">Security Guarantee</div>
                                    <p class="text-sm text-green-800 dark:text-green-200">
                                        The same <code class="font-mono bg-green-100 dark:bg-green-900/40 px-1 py-0.5 rounded text-xs">(suite_key, nonce)</code> pair is mathematically impossible to reuse. Counter uniqueness is enforced by the protocol state machine, and any violation triggers fail-closed rejection.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 6: Tag Verification & Fail-Closed -->
        <section class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Tag Verification & Fail-Closed Design
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Production-grade security through strict validation and fail-closed error handling.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-gray-50 dark:bg-slate-800 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Authentication Tag Verification</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            All C6P AEAD suites produce a <strong class="text-gray-900 dark:text-white">16-byte authentication tag</strong>. This tag cryptographically proves that:
                        </p>

                        <div class="grid md:grid-cols-2 gap-4 mb-6">
                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-green-600 dark:text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Authenticity</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Message was created by someone with the session key</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Integrity</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Ciphertext hasn't been tampered with</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-purple-600 dark:text-purple-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">AAD Binding</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Metadata (suite, stream, counter) is authentic</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-orange-600 dark:text-orange-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Context Lock</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Message can't be moved to different session</p>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Fail-Closed Philosophy</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            C6P follows a <strong class="text-gray-900 dark:text-white">fail-closed</strong> security model: when anything goes wrong, the system rejects the message rather than trying to recover.
                        </p>

                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Decryption & Verification Flow</div>
                            <div class="text-blue-400 mb-1">1. Validate envelope structure</div>
                            <div class="text-gray-500 ml-4 mb-2">↳ Known suite_id, stream_id, message_type</div>

                            <div class="text-green-400 mb-1">2. Reconstruct AAD from envelope + session state</div>
                            <div class="text-gray-500 ml-4 mb-2">↳ Must be exactly 63 bytes</div>

                            <div class="text-purple-400 mb-1">3. Derive suite_key and nonce</div>
                            <div class="text-gray-500 ml-4 mb-2">↳ From mk_material for this counter</div>

                            <div class="text-orange-400 mb-1">4. AEAD_Open(key, nonce, aad, sealed)</div>
                            <div class="text-gray-500 ml-4 mb-2">↳ Tag verification happens here</div>

                            <div class="text-red-400 mb-1">5. IF tag invalid → REJECT</div>
                            <div class="text-gray-500 ml-4 mb-2">↳ Do NOT advance ratchet, do NOT mark consumed</div>

                            <div class="text-yellow-400 mb-1">6. IF tag valid BUT counter replay → REJECT</div>
                            <div class="text-gray-500 ml-4 mb-2">↳ Even if decryption succeeds!</div>

                            <div class="text-green-400">7. IF all checks pass → Accept & advance state</div>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Violation Response</h3>

                        <div class="space-y-3 mb-6">
                            <div class="flex items-start gap-3 p-3 bg-red-50 dark:bg-red-900/20 rounded-lg border border-red-200 dark:border-red-800">
                                <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                </svg>
                                <div class="flex-1">
                                    <div class="font-semibold text-red-900 dark:text-red-100 text-sm mb-1">Tag Verification Failed</div>
                                    <p class="text-xs text-red-800 dark:text-red-300">Message rejected, state unchanged, security event logged</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3 p-3 bg-red-50 dark:bg-red-900/20 rounded-lg border border-red-200 dark:border-red-800">
                                <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                </svg>
                                <div class="flex-1">
                                    <div class="font-semibold text-red-900 dark:text-red-100 text-sm mb-1">Unknown Suite ID</div>
                                    <p class="text-xs text-red-800 dark:text-red-300">Rejected before any crypto operations</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3 p-3 bg-red-50 dark:bg-red-900/20 rounded-lg border border-red-200 dark:border-red-800">
                                <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                </svg>
                                <div class="flex-1">
                                    <div class="font-semibold text-red-900 dark:text-red-100 text-sm mb-1">Malformed Sizes</div>
                                    <p class="text-xs text-red-800 dark:text-red-300">Wrong session_id length, sealed too short, AAD mismatch</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3 p-3 bg-red-50 dark:bg-red-900/20 rounded-lg border border-red-200 dark:border-red-800">
                                <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                                </svg>
                                <div class="flex-1">
                                    <div class="font-semibold text-red-900 dark:text-red-100 text-sm mb-1">Counter Replay</div>
                                    <p class="text-xs text-red-800 dark:text-red-300">Duplicate counter detected — rejected even if AEAD verifies</p>
                                </div>
                            </div>
                        </div>

                        <div class="bg-red-50 dark:bg-red-900/20 border-l-4 border-red-600 dark:border-red-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-red-900 dark:text-red-100 mb-1">Hard Rule: No Recovery Attempts</div>
                                    <p class="text-sm text-red-800 dark:text-red-200">
                                        C6P implementations MUST NOT "try to recover" from cryptographic failures by guessing counters, accepting replays, or weakening validation. All violations trigger fail-closed rejection. This is non-negotiable for security.
                                    </p>
                                </div>
                            </div>
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
                                <p><strong>Forward secrecy</strong> protects past messages even if current state is compromised</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Symmetric ratchet</strong> advances one-way — past keys unrecoverable</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>ChaCha20-Poly1305</strong> production default — fast, battle-tested, constant-time</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Deterministic nonces</strong> safe by construction — per-message keys prevent reuse</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>16-byte tags</strong> cryptographically prove authenticity and integrity</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Fail-closed design</strong> — violations rejected, no recovery attempts</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

    </main>

    <?php include __DIR__ . '/../components/footer.php'; ?>

    <!-- Custom JavaScript -->
    <script src="<?= JS_PATH ?>/app.js"></script>

</body>
</html>
