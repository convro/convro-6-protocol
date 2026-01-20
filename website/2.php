<?php
$postNumber = $_POST_NUMBER ?? 2;
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

    <title>IslandAccord Handshake & Key Hierarchy - C6P Protocol Documentation</title>
    <meta name="description" content="Deep dive into IslandAccord v1 cryptographic handshake, 3DH/4DH key agreement, and the C6P hierarchical key schedule">

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
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                    </svg>
                    CRYPTOGRAPHIC HANDSHAKE
                </div>

                <h1 class="text-4xl md:text-5xl font-extrabold mb-6 drop-shadow-lg">
                    IslandAccord & The Key Hierarchy
                </h1>

                <p class="text-lg md:text-xl text-purple-200 mb-10 max-w-3xl mx-auto drop-shadow-sm">
                    How C6P v1 establishes authenticated sessions through IslandAccord handshake and derives hierarchical keys for perfect forward secrecy.
                </p>

                <!-- Stats Grid -->
                <div class="grid grid-cols-2 md:grid-cols-4 gap-4 max-w-3xl mx-auto mb-10">
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">3DH+OTP</div>
                        <div class="text-sm text-purple-200">Key Agreement</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">Ed25519</div>
                        <div class="text-sm text-purple-200">Authentication</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">3-Tier</div>
                        <div class="text-sm text-purple-200">Key Hierarchy</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">HKDF</div>
                        <div class="text-sm text-purple-200">Derivation</div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 1: IslandAccord Overview -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        What is IslandAccord v1?
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        An authenticated prekey handshake protocol providing mutual authentication and session establishment.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-white dark:bg-slate-900 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <p class="text-lg text-gray-600 dark:text-gray-400 mb-6 leading-relaxed">
                            <strong class="text-gray-900 dark:text-white">IslandAccord v1</strong> is C6P's canonical authenticated prekey handshake. It combines X25519 Diffie-Hellman key agreement with Ed25519 signatures to provide:
                        </p>

                        <div class="grid md:grid-cols-2 gap-6 mb-8">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h3 class="font-bold text-gray-900 dark:text-white mb-2">Server Blindness</h3>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Server never learns session secrets — all cryptography happens client-side</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h3 class="font-bold text-gray-900 dark:text-white mb-2">Initiator Authentication</h3>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Responder cryptographically verifies initiator identity via transcript-bound Ed25519 signature</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h3 class="font-bold text-gray-900 dark:text-white mb-2">Explicit Key Confirmation</h3>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Both parties prove they derived identical secrets before session activation</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h3 class="font-bold text-gray-900 dark:text-white mb-2">Downgrade Resistance</h3>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Protocol version and cipher suite are transcript-bound and signature-bound</p>
                                </div>
                            </div>
                        </div>

                        <!-- Info callout -->
                        <div class="bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-600 dark:border-blue-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-blue-900 dark:text-blue-100 mb-1">Production Status</div>
                                    <p class="text-sm text-blue-800 dark:text-blue-200">
                                        IslandAccord v1 is <strong>PRODUCTION/CANONICAL/NORMATIVE</strong>. All implementations must follow the specification exactly. Any deviation breaks interoperability and security guarantees.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 2: 3DH + 4DH Handshake -->
        <section class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        The DH Set: 3DH + Optional OTP
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        IslandAccord uses three mandatory Diffie-Hellman operations, plus an optional fourth for enhanced security.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-gray-50 dark:bg-slate-800 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Key Material Overview</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6 leading-relaxed">
                            Each party maintains long-term and ephemeral keys:
                        </p>

                        <!-- Keys table -->
                        <div class="overflow-x-auto rounded-xl border border-gray-200 dark:border-gray-700 mb-6">
                            <table class="w-full">
                                <thead class="bg-gray-100 dark:bg-slate-950">
                                    <tr>
                                        <th class="px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-white">Party</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-white">Key Type</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-white">Purpose</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">Alice (Init)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">IK_dh (X25519)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Long-term identity DH key</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">Alice</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">IK_sig (Ed25519)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Long-term signing key for authentication</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">Alice</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">EK (X25519)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Fresh ephemeral per-session</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-purple-600 dark:text-purple-400">Bob (Resp)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">IK_dh (X25519)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Long-term identity DH key</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-purple-600 dark:text-purple-400">Bob</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">SPK (X25519)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Signed prekey (rotated periodically)</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-purple-600 dark:text-purple-400">Bob</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">OTP (X25519)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">One-time prekey (single-use, optional)</td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">DH Computations</h3>

                        <!-- DH operations diagram -->
                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-green-400 mb-1 font-bold">// Mandatory DHs (3DH)</div>
                            <div class="text-blue-400 mb-1">DH1 = X25519(A_IK_dh_priv, B_SPK_pub)</div>
                            <div class="text-gray-500 ml-4 mb-1">↳ Long-term initiator × rotating responder prekey</div>
                            <div class="text-blue-400 mb-1">DH2 = X25519(A_EK_priv, B_IK_dh_pub)</div>
                            <div class="text-gray-500 ml-4 mb-1">↳ Ephemeral initiator × long-term responder</div>
                            <div class="text-blue-400 mb-3">DH3 = X25519(A_EK_priv, B_SPK_pub)</div>
                            <div class="text-gray-500 ml-4 mb-3">↳ Ephemeral initiator × rotating responder prekey</div>

                            <div class="text-green-400 mb-1 font-bold">// Optional 4th DH (when OTP is used)</div>
                            <div class="text-purple-400 mb-1">DH4 = X25519(A_EK_priv, B_OTP_pub)</div>
                            <div class="text-gray-500 ml-4 mb-3">↳ Ephemeral initiator × one-time responder prekey</div>

                            <div class="text-green-400 mb-1 font-bold">// Input Key Material</div>
                            <div class="text-yellow-400">IKM = DH1 || DH2 || DH3 || [DH4]</div>
                            <div class="text-gray-500 ml-4">↳ Length: 96 bytes (no OTP) or 128 bytes (with OTP)</div>
                        </div>

                        <!-- Security property callout -->
                        <div class="bg-green-50 dark:bg-green-900/20 border-l-4 border-green-600 dark:border-green-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-green-600 dark:text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-green-900 dark:text-green-100 mb-1">Security Property</div>
                                    <p class="text-sm text-green-800 dark:text-green-200">
                                        The 3DH set ensures that compromise of any single long-term key (IK_dh or SPK) doesn't compromise session keys. The optional OTP adds an extra layer: even if both long-term keys are compromised, past sessions with OTP remain secure.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 3: Canonical Transcript & Authentication -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Transcript Binding & Authentication
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Every handshake parameter is bound into a canonical transcript, protecting against server splicing and downgrade attacks.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-white dark:bg-slate-900 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Canonical Transcript Construction</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            The transcript is the single source of truth for binding. It includes (in exact order):
                        </p>

                        <!-- Transcript fields -->
                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Canonical Transcript Fields (Exact Order)</div>
                            <div class="text-gray-300 mb-1">1. <span class="text-yellow-400">"ISLAND_ACCORD_V1"</span> (label)</div>
                            <div class="text-gray-300 mb-1">2. <span class="text-blue-400">IA_VERSION</span> (u8 = 0x01)</div>
                            <div class="text-gray-300 mb-1">3. <span class="text-blue-400">C6P_VERSION</span> (u8 = 0x01)</div>
                            <div class="text-gray-300 mb-1">4. <span class="text-blue-400">suite_id</span> (u8)</div>
                            <div class="text-gray-300 mb-1">5. <span class="text-blue-400">sessionId</span> (8 bytes)</div>
                            <div class="text-gray-300 mb-1">6. <span class="text-blue-400">A_deviceId</span> (16 bytes)</div>
                            <div class="text-gray-300 mb-1">7. <span class="text-blue-400">B_deviceId</span> (16 bytes)</div>
                            <div class="text-gray-300 mb-1">8. <span class="text-purple-400">A_IK_dh_pub</span> (32 bytes)</div>
                            <div class="text-gray-300 mb-1">9. <span class="text-purple-400">A_IK_sig_pub</span> (32 bytes)</div>
                            <div class="text-gray-300 mb-1">10. <span class="text-purple-400">A_EK_pub</span> (32 bytes)</div>
                            <div class="text-gray-300 mb-1">11. <span class="text-green-400">B_IK_dh_pub</span> (32 bytes)</div>
                            <div class="text-gray-300 mb-1">12. <span class="text-green-400">B_IK_sig_pub</span> (32 bytes)</div>
                            <div class="text-gray-300 mb-1">13. <span class="text-green-400">spkId</span> (8 bytes)</div>
                            <div class="text-gray-300 mb-1">14. <span class="text-green-400">spkPub</span> (32 bytes)</div>
                            <div class="text-gray-300 mb-1">15. <span class="text-green-400">spkSig</span> (64 bytes)</div>
                            <div class="text-gray-300 mb-1">16. <span class="text-orange-400">otpFlag</span> (1 byte: 0x01 or 0x00)</div>
                            <div class="text-gray-300">17. <span class="text-orange-400">otpId + otpPub</span> (if flag = 0x01)</div>
                            <div class="text-gray-500 mt-3">↓</div>
                            <div class="text-yellow-400 mt-1">transcript_hash = SHA256(T)</div>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Initiator Authentication</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-4">
                            The initiator proves their identity by signing a hash of the transcript and session parameters:
                        </p>

                        <!-- Signature construction -->
                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Offer Signature (Initiator Authentication)</div>
                            <pre class="text-gray-300"><code>sig_input = SHA256(
    "IA_OFFER_SIG_V1" ||
    transcript_hash(32) ||
    U8(C6P_VERSION) ||
    U8(suite_id) ||
    sessionId(8) ||
    A_deviceId(16) ||
    B_deviceId(16)
)

offer_signature = Ed25519.Sign(A_IK_sig_priv, sig_input)</code></pre>
                        </div>

                        <!-- Critical warning -->
                        <div class="bg-red-50 dark:bg-red-900/20 border-l-4 border-red-600 dark:border-red-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-red-900 dark:text-red-100 mb-1">Fail-Closed Requirement</div>
                                    <p class="text-sm text-red-800 dark:text-red-200">
                                        If transcript hashes don't match or signature verification fails, the handshake MUST abort immediately. The responder MUST NOT create an active session. Any mismatch indicates either an active attack or implementation bug.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 4: Key Hierarchy -->
        <section class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Three-Tier Key Hierarchy
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Root → Chain → Message: a hierarchical derivation ensuring forward secrecy and domain separation.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-gray-50 dark:bg-slate-800 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">Tier 1: Root Key Derivation</h3>

                        <!-- Root key derivation -->
                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Root Key (from IslandAccord IKM)</div>
                            <pre class="text-gray-300"><code>CTX = session_id(8) || initiator_device_id(16) || responder_device_id(16)

salt_root = SHA256("C6P_ROOT_V1" || CTX || transcript_hash)

prk_root = HKDF-Extract(salt=salt_root, ikm=IKM)

root_key = HKDF-Expand(prk_root,
                       info="C6P_ROOT_V1" || U8(0x01),
                       L=32)</code></pre>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">Tier 2: Stream Chain Keys</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-4">
                            Each session has two independent directional chain keys:
                        </p>

                        <!-- Chain key derivation -->
                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Chain Keys (i2r and r2i streams)</div>
                            <pre class="text-gray-300"><code>STREAM_CTX = U8(stream_id) || U8(message_type) || U8(suite_id)

salt_chain = SHA256("C6P_CHAIN_V1" || CTX || transcript_hash)

prk_chain = HKDF-Extract(salt=salt_chain, ikm=root_key)

// For stream_id ∈ {0x01 i2r, 0x02 r2i}
CK_stream = HKDF-Expand(prk_chain,
                        info="C6P_CHAIN_V1" || U8(0x01) || STREAM_CTX,
                        L=32)</code></pre>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">Tier 3: Per-Message Keys</h3>

                        <!-- Per-message derivation -->
                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Message Key Material + Ratchet Step</div>
                            <pre class="text-gray-300"><code>salt_msg = SHA256("C6P_MSG_V1" || CTX || transcript_hash ||
                   STREAM_CTX || BE64(counter))

prk_msg = HKDF-Extract(salt=salt_msg, ikm=chain_key)

// Message key material (32 bytes)
mk_material = HKDF-Expand(prk_msg,
                          info="C6P_MSG_V1" || U8(0x01) || STREAM_CTX,
                          L=32)

// Next chain key (ratchet forward)
next_chain_key = HKDF-Expand(prk_msg,
                             info="C6P_CHAIN_V1" || U8(0x01) ||
                                  STREAM_CTX || BE64(counter),
                             L=32)</code></pre>
                        </div>

                        <!-- Visual hierarchy -->
                        <div class="bg-gradient-to-br from-purple-50 to-indigo-50 dark:from-purple-900/20 dark:to-indigo-900/20 rounded-xl p-6 border border-purple-200 dark:border-purple-700">
                            <h4 class="font-bold text-gray-900 dark:text-white mb-4 flex items-center gap-2">
                                <svg class="w-5 h-5 text-purple-600 dark:text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z"/>
                                </svg>
                                Key Hierarchy Visualization
                            </h4>
                            <div class="font-mono text-sm text-gray-700 dark:text-gray-300">
                                <div class="mb-1">📦 IslandAccord IKM (DH1||DH2||DH3||[DH4])</div>
                                <div class="ml-4 mb-1">└─ 🔑 <span class="font-bold text-purple-600 dark:text-purple-400">Root Key</span> (32 bytes, session-bound)</div>
                                <div class="ml-8 mb-1">├─ 🔗 <span class="font-bold text-blue-600 dark:text-blue-400">Chain Key i2r</span> (initiator → responder)</div>
                                <div class="ml-12 mb-1">│  ├─ 📨 Message Key counter=0</div>
                                <div class="ml-12 mb-1">│  ├─ 📨 Message Key counter=1</div>
                                <div class="ml-12 mb-1">│  └─ 📨 Message Key counter=2...</div>
                                <div class="ml-8 mb-1">└─ 🔗 <span class="font-bold text-green-600 dark:text-green-400">Chain Key r2i</span> (responder → initiator)</div>
                                <div class="ml-12 mb-1">   ├─ 📨 Message Key counter=0</div>
                                <div class="ml-12 mb-1">   ├─ 📨 Message Key counter=1</div>
                                <div class="ml-12">   └─ 📨 Message Key counter=2...</div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 5: Domain Separation & Deterministic Nonces -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Domain Separation & Nonces
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Strict domain labels prevent key reuse across contexts. Deterministic nonces are safe by design.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-white dark:bg-slate-900 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Domain Separation Labels</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            Every derivation uses a unique ASCII label to prevent cross-context key reuse:
                        </p>

                        <!-- Domain labels table -->
                        <div class="overflow-x-auto rounded-xl border border-gray-200 dark:border-gray-700 mb-8">
                            <table class="w-full">
                                <thead class="bg-gray-100 dark:bg-slate-950">
                                    <tr>
                                        <th class="px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-white">Label</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold text-gray-900 dark:text-white">Purpose</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">C6P_ROOT_V1</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Root key derivation from IKM</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">C6P_CHAIN_V1</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Stream chain keys and ratcheting</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">C6P_MSG_V1</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Per-message key material</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">C6P_NONCE_V1</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Deterministic nonce derivation</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">C6P_KC_V1</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Key confirmation tags</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-gray-500 dark:text-gray-500">C6P_REKEY_V1</td>
                                        <td class="px-6 py-4 text-sm text-gray-500 dark:text-gray-500">Reserved for future rekey operations</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-gray-500 dark:text-gray-500">C6P_EXPORT_V1</td>
                                        <td class="px-6 py-4 text-sm text-gray-500 dark:text-gray-500">Reserved for app-level export keys</td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Deterministic Nonce Derivation</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-4">
                            C6P uses deterministic nonces, which is safe because each message uses a unique ephemeral key:
                        </p>

                        <!-- Nonce derivation -->
                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Nonce Derivation (Suite-Specific Length)</div>
                            <pre class="text-gray-300"><code>session_binding = SHA256("C6P_BIND_V1" || session_id(8) ||
                           initiator_device_id(16) ||
                           responder_device_id(16))

prk_nonce = HKDF-Extract(salt=session_binding, ikm=mk_material)

nonce_info = "C6P_NONCE_V1" ||
             U8(0x01) ||
             U8(suite_id) ||
             U8(message_type) ||
             U8(stream_id) ||
             session_id(8) ||
             BE64(counter)

nonce = HKDF-Expand(prk_nonce, info=nonce_info, L=nonce_len)

// Nonce lengths:
// ChaCha20-Poly1305:   12 bytes
// XChaCha20-Poly1305:  24 bytes
// AEGIS-128L:          16 bytes</code></pre>
                        </div>

                        <!-- Safety callout -->
                        <div class="bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-600 dark:border-blue-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-blue-900 dark:text-blue-100 mb-1">Why Deterministic Nonces Are Safe</div>
                                    <p class="text-sm text-blue-800 dark:text-blue-200">
                                        Deterministic nonces are permitted because: (1) every message uses a unique <code class="font-mono bg-blue-100 dark:bg-blue-900/40 px-1 py-0.5 rounded">mk_material</code> derived from <code class="font-mono bg-blue-100 dark:bg-blue-900/40 px-1 py-0.5 rounded">(session, stream, counter)</code>, (2) nonce derivation binds all context including counter, and (3) replay detection rejects duplicate counters even if AEAD verifies.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 6: Test Vectors & Cross-Implementation Validation -->
        <section class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Test Vectors & Validation
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Canonical test vectors ensure bit-for-bit compatibility across Rust, Swift, and Node implementations.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-gray-50 dark:bg-slate-800 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Handshake Test Vectors</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            IslandAccord v1 includes comprehensive test vectors for cross-implementation validation:
                        </p>

                        <!-- Vector files list -->
                        <div class="grid md:grid-cols-2 gap-4 mb-8">
                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-purple-600 dark:text-purple-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                                    </svg>
                                    <div>
                                        <div class="font-mono text-sm font-bold text-gray-900 dark:text-white mb-1">island_accord_offer_vectors.json</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Offer construction, SPK signature, transcript hash, offer signature</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                                    </svg>
                                    <div>
                                        <div class="font-mono text-sm font-bold text-gray-900 dark:text-white mb-1">initiator_derive_vectors.json</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">DH computation, IKM, root/KC derivation, KC1</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-green-600 dark:text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                                    </svg>
                                    <div>
                                        <div class="font-mono text-sm font-bold text-gray-900 dark:text-white mb-1">responder_derive_vectors.json</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Mirrored DH, KC1 verification, KC2 computation</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-red-600 dark:text-red-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"/>
                                    </svg>
                                    <div>
                                        <div class="font-mono text-sm font-bold text-gray-900 dark:text-white mb-1">negative_vectors.json</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Invalid signatures, transcript mismatches, encoding errors</p>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Crypto Core Test Vectors</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            Key schedule and AEAD operations have dedicated vectors:
                        </p>

                        <!-- Crypto vectors -->
                        <div class="grid md:grid-cols-2 gap-4 mb-8">
                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="font-mono text-sm font-bold text-gray-900 dark:text-white mb-1">key_schedule_vectors.json</div>
                                <p class="text-xs text-gray-600 dark:text-gray-400">Root, chain, and per-message key derivations</p>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="font-mono text-sm font-bold text-gray-900 dark:text-white mb-1">nonce_vectors.json</div>
                                <p class="text-xs text-gray-600 dark:text-gray-400">Deterministic nonce for all suites (ChaCha20, XChaCha20, AEGIS)</p>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="font-mono text-sm font-bold text-gray-900 dark:text-white mb-1">aead_vectors_*.json</div>
                                <p class="text-xs text-gray-600 dark:text-gray-400">End-to-end seal/open with AAD for each suite</p>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="font-mono text-sm font-bold text-gray-900 dark:text-white mb-1">replay_skipwindow_vectors.json</div>
                                <p class="text-xs text-gray-600 dark:text-gray-400">Skip-window acceptance and replay rejection scenarios</p>
                            </div>
                        </div>

                        <!-- Vector generation info -->
                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Generating Test Vectors</div>
                            <div class="text-green-400 mb-1">$ cd rust</div>
                            <div class="text-blue-400 mb-1">$ cargo run --package c6p-test-vectors --bin c6p-gen-vectors \</div>
                            <div class="text-blue-400 ml-4 mb-1">  --output test-vectors --force --verbose</div>
                            <div class="text-gray-500 mt-3">Output: rust/test-vectors/{handshake,crypto}/test-vectors/v1/</div>
                        </div>

                        <!-- CI requirement -->
                        <div class="bg-yellow-50 dark:bg-yellow-900/20 border-l-4 border-yellow-600 dark:border-yellow-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-yellow-600 dark:text-yellow-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-yellow-900 dark:text-yellow-100 mb-1">CI Enforcement</div>
                                    <p class="text-sm text-yellow-800 dark:text-yellow-200">
                                        <strong>Hard rule:</strong> All implementations (Rust/Swift/Node) MUST pass test vectors bit-for-bit. CI MUST fail on any mismatch. This ensures identical cryptographic behavior across platforms.
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
                                <p><strong>IslandAccord provides mutual authentication</strong> without server learning session secrets</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>3DH + optional OTP</strong> ensures compromise of single long-term key doesn't break sessions</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Three-tier key hierarchy</strong> (root → chain → message) enables perfect forward secrecy</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Domain separation labels</strong> prevent key reuse across different cryptographic contexts</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Deterministic nonces are safe</strong> because every message uses unique ephemeral keys</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Test vectors ensure interoperability</strong> across Rust, Swift, and Node implementations</p>
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
