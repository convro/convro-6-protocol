<?php
$postNumber = $_POST_NUMBER ?? 4;
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

    <title>Virtual Numbers & Multi-Device Identity - C6P Protocol</title>
    <meta name="description" content="How C6P's +99 virtual number system and multi-device architecture provide privacy, flexibility, and seamless cross-device messaging">

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
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z"/>
                    </svg>
                    IDENTITY & MULTI-DEVICE
                </div>

                <h1 class="text-4xl md:text-5xl font-extrabold mb-6 drop-shadow-lg">
                    Virtual Numbers & Multi-Device Magic
                </h1>

                <p class="text-lg md:text-xl text-purple-200 mb-10 max-w-3xl mx-auto drop-shadow-sm">
                    How C6P's +99 virtual number system provides privacy-first identity while supporting seamless multi-device messaging with independent cryptographic keys.
                </p>

                <div class="grid grid-cols-2 md:grid-cols-4 gap-4 max-w-3xl mx-auto mb-10">
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">+99</div>
                        <div class="text-sm text-purple-200">Virtual Prefix</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">No SIM</div>
                        <div class="text-sm text-purple-200">Required</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">∞</div>
                        <div class="text-sm text-purple-200">Devices</div>
                    </div>
                    <div class="bg-white/10 backdrop-blur-sm rounded-xl p-4 border border-white/20">
                        <div class="text-2xl font-bold">Ed25519</div>
                        <div class="text-sm text-purple-200">Per Device</div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 1: The +99 Virtual Number System -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        The +99 Virtual Number System
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Your identity is a permanent virtual number — no SIM card, no phone company, no tracking.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-white dark:bg-slate-900 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">What is a +99 Number?</h3>

                        <p class="text-lg text-gray-600 dark:text-gray-400 mb-6 leading-relaxed">
                            Every Convro account has a <strong class="text-gray-900 dark:text-white">permanent virtual number</strong> in the <code class="font-mono bg-gray-100 dark:bg-slate-800 px-2 py-1 rounded text-purple-600 dark:text-purple-400">+99 xxx xxx</code> namespace. For example: <strong class="text-gray-900 dark:text-white">+99 241 772</strong>
                        </p>

                        <div class="grid md:grid-cols-2 gap-6 mb-8">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h4 class="font-bold text-gray-900 dark:text-white mb-2">No SIM Required</h4>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Your identity isn't tied to a phone carrier or physical SIM card</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h4 class="font-bold text-gray-900 dark:text-white mb-2">Permanent Identity</h4>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">Your +99 number is yours for life — never reassigned or rotated</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h4 class="font-bold text-gray-900 dark:text-white mb-2">Privacy by Design</h4>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">No real phone number means no SMS intercepts or carrier tracking</p>
                                </div>
                            </div>

                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-600 dark:text-green-400 flex-shrink-0 mt-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <div>
                                    <h4 class="font-bold text-gray-900 dark:text-white mb-2">Canonical Identifier</h4>
                                    <p class="text-sm text-gray-600 dark:text-gray-400">All cryptographic operations bind to your +99 number internally</p>
                                </div>
                            </div>
                        </div>

                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Example Virtual Number</div>
                            <div class="text-green-400 text-2xl mb-2">+99 241 772</div>
                            <div class="text-gray-500 text-xs">↓ Maps internally to</div>
                            <div class="text-blue-400 mb-1">user_id: 550e8400-e29b-41d4-a716-446655440000</div>
                            <div class="text-purple-400">username: @alice (optional)</div>
                        </div>

                        <div class="bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-600 dark:border-blue-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-blue-900 dark:text-blue-100 mb-1">Why +99?</div>
                                    <p class="text-sm text-blue-800 dark:text-blue-200">
                                        The +99 prefix is a <strong>reserved country code</strong> that doesn't correspond to any real country. This makes it clear these are virtual identities, not tied to any nation or telecom provider.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 2: Device Identity Model -->
        <section class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        One Device = One Identity
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Each device installation generates its own cryptographic identity, independent from all others.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-gray-50 dark:bg-slate-800 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Device Identity Components</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            Every device has its own long-term keypairs that never leave the device:
                        </p>

                        <div class="overflow-x-auto rounded-xl border border-gray-200 dark:border-gray-700 mb-6">
                            <table class="w-full">
                                <thead class="bg-gray-800 dark:bg-slate-950 text-white">
                                    <tr>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Component</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Type</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Purpose</th>
                                        <th class="px-6 py-3 text-left text-sm font-semibold">Size</th>
                                    </tr>
                                </thead>
                                <tbody class="divide-y divide-gray-200 dark:divide-gray-700">
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-purple-600 dark:text-purple-400">IK_sig</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Ed25519</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Signing & Authentication</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">32 bytes pub + 64 bytes priv</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-blue-600 dark:text-blue-400">IK_dh</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">X25519</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Key Exchange (DH)</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">32 bytes pub + 32 bytes priv</td>
                                    </tr>
                                    <tr class="bg-white dark:bg-slate-900 hover:bg-gray-50 dark:hover:bg-slate-800 transition-colors">
                                        <td class="px-6 py-4 font-mono text-sm text-green-600 dark:text-green-400">device_id</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">SHA-256</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">Derived from IK_sig</td>
                                        <td class="px-6 py-4 text-sm text-gray-600 dark:text-gray-400">16 bytes (hex32)</td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Device ID Derivation</h3>

                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Canonical Device ID Generation</div>
                            <pre class="text-gray-300"><code>device_id = SHA-256(
    "C6P_DEVICE_ID_V1" ||
    IK_sig_pub_bytes(32)
)[0..16]

// Output: 16 bytes
// Wire encoding: hex32 lowercase
// Example: "0123456789abcdef0123456789abcdef"</code></pre>
                        </div>

                        <div class="grid md:grid-cols-2 gap-4 mb-6">
                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-purple-600 dark:text-purple-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Deterministic</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Same IK_sig always produces same device_id — stable across restores</p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>
                                    </svg>
                                    <div>
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Secure Storage</div>
                                        <p class="text-xs text-gray-600 dark:text-gray-400">Private keys stored in iOS Keychain / Android KeyStore only</p>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div class="bg-green-50 dark:bg-green-900/20 border-l-4 border-green-600 dark:border-green-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-green-600 dark:text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-green-900 dark:text-green-100 mb-1">Security Property</div>
                                    <p class="text-sm text-green-800 dark:text-green-200">
                                        <strong>Server never learns private keys.</strong> Identity generation happens entirely on-device. The server only sees public keys during registration.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 3: Multi-Device Architecture -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Multi-Device: Same User, Independent Keys
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Use Convro on iPhone, iPad, Mac, and Android — each with its own cryptographic identity linked to your +99 number.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-white dark:bg-slate-900 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-6">Account → Devices Mapping</h3>

                        <div class="bg-gradient-to-br from-purple-50 to-indigo-50 dark:from-purple-900/20 dark:to-indigo-900/20 rounded-xl p-6 border border-purple-200 dark:border-purple-700 mb-6">
                            <div class="font-mono text-sm text-gray-700 dark:text-gray-300">
                                <div class="mb-1">👤 <span class="font-bold text-purple-600 dark:text-purple-400">User: +99 241 772</span> (@alice)</div>
                                <div class="ml-4 mb-1">├─ 📱 <span class="font-bold text-blue-600 dark:text-blue-400">iPhone 15 Pro</span></div>
                                <div class="ml-8 mb-1">│  ├─ device_id: <span class="text-xs">0123...cdef</span></div>
                                <div class="ml-8 mb-1">│  ├─ IK_sig: Ed25519 (pub: <span class="text-xs">AAAA...ZZZZ</span>)</div>
                                <div class="ml-8 mb-3">│  └─ IK_dh: X25519 (pub: <span class="text-xs">BBBB...YYYY</span>)</div>

                                <div class="ml-4 mb-1">├─ 💻 <span class="font-bold text-green-600 dark:text-green-400">MacBook Pro</span></div>
                                <div class="ml-8 mb-1">│  ├─ device_id: <span class="text-xs">4567...89ab</span></div>
                                <div class="ml-8 mb-1">│  ├─ IK_sig: Ed25519 (pub: <span class="text-xs">CCCC...XXXX</span>)</div>
                                <div class="ml-8 mb-3">│  └─ IK_dh: X25519 (pub: <span class="text-xs">DDDD...WWWW</span>)</div>

                                <div class="ml-4 mb-1">└─ 📱 <span class="font-bold text-orange-600 dark:text-orange-400">iPad Air</span></div>
                                <div class="ml-8 mb-1">   ├─ device_id: <span class="text-xs">cdef...0123</span></div>
                                <div class="ml-8 mb-1">   ├─ IK_sig: Ed25519 (pub: <span class="text-xs">EEEE...VVVV</span>)</div>
                                <div class="ml-8">   └─ IK_dh: X25519 (pub: <span class="text-xs">FFFF...UUUU</span>)</div>
                            </div>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Why Separate Identities Per Device?</h3>

                        <div class="space-y-4 mb-6">
                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <div class="bg-purple-600 text-white rounded-full w-8 h-8 flex items-center justify-center flex-shrink-0 font-bold">1</div>
                                    <div class="flex-1">
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Independent Compromise Scope</div>
                                        <p class="text-sm text-gray-600 dark:text-gray-400">
                                            If your iPhone is compromised, your MacBook sessions remain secure. Each device has independent cryptographic keys.
                                        </p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <div class="bg-blue-600 text-white rounded-full w-8 h-8 flex items-center justify-center flex-shrink-0 font-bold">2</div>
                                    <div class="flex-1">
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Platform-Specific Security</div>
                                        <p class="text-sm text-gray-600 dark:text-gray-400">
                                            iOS Keychain, Android KeyStore, macOS Secure Enclave — each platform's native security works independently.
                                        </p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <div class="bg-green-600 text-white rounded-full w-8 h-8 flex items-center justify-center flex-shrink-0 font-bold">3</div>
                                    <div class="flex-1">
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">Granular Revocation</div>
                                        <p class="text-sm text-gray-600 dark:text-gray-400">
                                            Lost your phone? Revoke just that device. Your other devices keep working without re-keying everything.
                                        </p>
                                    </div>
                                </div>
                            </div>

                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-4 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-start gap-3">
                                    <div class="bg-orange-600 text-white rounded-full w-8 h-8 flex items-center justify-center flex-shrink-0 font-bold">4</div>
                                    <div class="flex-1">
                                        <div class="font-bold text-gray-900 dark:text-white mb-1">No Key Syncing</div>
                                        <p class="text-sm text-gray-600 dark:text-gray-400">
                                            Private keys never leave the device they were generated on. No cloud backup, no syncing risk.
                                        </p>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div class="bg-yellow-50 dark:bg-yellow-900/20 border-l-4 border-yellow-600 dark:border-yellow-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-yellow-600 dark:text-yellow-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-yellow-900 dark:text-yellow-100 mb-1">History is Per-Device</div>
                                    <p class="text-sm text-yellow-800 dark:text-yellow-200">
                                        New devices don't automatically get message history from existing devices. Each device starts fresh with its own cryptographic sessions. This is a <strong>privacy-first design choice</strong>.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 4: Prekey Bundles -->
        <section class="py-20 bg-white dark:bg-slate-900" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Prekey Bundles: Starting New Sessions
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        How devices discover each other and establish encrypted sessions through signed prekeys.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-gray-50 dark:bg-slate-800 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">What is a Prekey Bundle?</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            A prekey bundle contains a device's public keys that allow others to initiate encrypted sessions without prior coordination.
                        </p>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Bundle Components</h3>

                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Prekey Bundle Structure</div>
                            <div class="text-gray-300 mb-1">📦 <span class="text-yellow-400">Prekey Bundle</span></div>
                            <div class="ml-4 text-gray-300 mb-1">├─ <span class="text-blue-400">IK_sig_pub</span> <span class="text-gray-500">(Ed25519, 32 bytes)</span></div>
                            <div class="ml-4 text-gray-300 mb-1">├─ <span class="text-blue-400">IK_dh_pub</span> <span class="text-gray-500">(X25519, 32 bytes)</span></div>
                            <div class="ml-4 text-gray-300 mb-1">├─ <span class="text-purple-400">SPK (Signed Prekey)</span></div>
                            <div class="ml-8 text-gray-300 mb-1">│  ├─ spkId <span class="text-gray-500">(8 bytes)</span></div>
                            <div class="ml-8 text-gray-300 mb-1">│  ├─ spkPub <span class="text-gray-500">(X25519, 32 bytes)</span></div>
                            <div class="ml-8 text-gray-300 mb-3">│  └─ spkSig <span class="text-gray-500">(Ed25519 signature, 64 bytes)</span></div>
                            <div class="ml-4 text-gray-300">└─ <span class="text-green-400">OTP (One-Time Prekey)</span> <span class="text-gray-500">(Optional)</span></div>
                            <div class="ml-8 text-gray-300 mb-1">   ├─ otpId <span class="text-gray-500">(8 bytes)</span></div>
                            <div class="ml-8 text-gray-300">   └─ otpPub <span class="text-gray-500">(X25519, 32 bytes)</span></div>
                        </div>

                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">Prekey Lifecycle</h3>

                        <div class="grid md:grid-cols-2 gap-6 mb-6">
                            <div class="bg-white dark:bg-slate-900 rounded-lg p-5 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-center gap-3 mb-3">
                                    <div class="bg-purple-600 text-white rounded-lg px-3 py-1 text-sm font-bold">SPK</div>
                                    <h4 class="font-bold text-gray-900 dark:text-white">Signed Prekey</h4>
                                </div>
                                <ul class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
                                    <li class="flex items-start gap-2">
                                        <span class="text-purple-600 dark:text-purple-400">•</span>
                                        <span>Rotated every <strong>30 days</strong></span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-purple-600 dark:text-purple-400">•</span>
                                        <span>Medium-term DH component (DH1, DH3)</span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-purple-600 dark:text-purple-400">•</span>
                                        <span>Signed by IK_sig for authenticity</span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-purple-600 dark:text-purple-400">•</span>
                                        <span>Server verifies signature on upload</span>
                                    </li>
                                </ul>
                            </div>

                            <div class="bg-white dark:bg-slate-900 rounded-lg p-5 border border-gray-200 dark:border-gray-700">
                                <div class="flex items-center gap-3 mb-3">
                                    <div class="bg-green-600 text-white rounded-lg px-3 py-1 text-sm font-bold">OTP</div>
                                    <h4 class="font-bold text-gray-900 dark:text-white">One-Time Prekey</h4>
                                </div>
                                <ul class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
                                    <li class="flex items-start gap-2">
                                        <span class="text-green-600 dark:text-green-400">•</span>
                                        <span>Single-use only (consumed atomically)</span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-green-600 dark:text-green-400">•</span>
                                        <span>Pool of ~100 OTPs per device</span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-green-600 dark:text-green-400">•</span>
                                        <span>Enhanced forward secrecy (4DH)</span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-green-600 dark:text-green-400">•</span>
                                        <span>Auto-refilled when pool drops below 20</span>
                                    </li>
                                </ul>
                            </div>
                        </div>

                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm overflow-x-auto mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Session Initiation Flow</div>
                            <div class="text-blue-400 mb-1">1. Alice wants to message Bob (+99 654 321)</div>
                            <div class="text-gray-500 ml-4 mb-2">GET /v1/prekeys/bundle?convroNumber=+99654321</div>

                            <div class="text-green-400 mb-1">2. Server returns Bob's prekey bundle</div>
                            <div class="text-gray-500 ml-4 mb-2">{ IK_sig_pub, IK_dh_pub, SPK, OTP }</div>

                            <div class="text-purple-400 mb-1">3. Alice performs 3DH (or 4DH with OTP)</div>
                            <div class="text-gray-500 ml-4 mb-2">DH1 = X25519(A_IK_dh, B_SPK)</div>
                            <div class="text-gray-500 ml-4 mb-2">DH2 = X25519(A_EK, B_IK_dh)</div>
                            <div class="text-gray-500 ml-4 mb-2">DH3 = X25519(A_EK, B_SPK)</div>
                            <div class="text-gray-500 ml-4 mb-3">DH4 = X25519(A_EK, B_OTP) [if OTP present]</div>

                            <div class="text-yellow-400 mb-1">4. Alice derives session keys from IKM</div>
                            <div class="text-gray-500 ml-4 mb-2">IKM = DH1 || DH2 || DH3 || [DH4]</div>

                            <div class="text-orange-400">5. Alice sends encrypted offer to Bob</div>
                        </div>

                        <div class="bg-blue-50 dark:bg-blue-900/20 border-l-4 border-blue-600 dark:border-blue-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-blue-900 dark:text-blue-100 mb-1">Asynchronous Messaging</div>
                                    <p class="text-sm text-blue-800 dark:text-blue-200">
                                        Prekey bundles enable asynchronous messaging. Alice can start a session with Bob even if Bob is offline. When Bob comes online, he decrypts using his local private keys.
                                    </p>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </section>

        <!-- Section 5: Username Aliases -->
        <section class="py-20 bg-gray-50 dark:bg-slate-800" data-animate>
            <div class="container mx-auto px-4">
                <div class="text-center mb-16">
                    <h2 class="text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-4">
                        Usernames: Human-Friendly Aliases
                    </h2>
                    <p class="text-lg text-gray-600 dark:text-gray-400 max-w-2xl mx-auto">
                        Optional usernames make Convro easier to use, while cryptography binds to your permanent +99 number.
                    </p>
                </div>

                <div class="max-w-4xl mx-auto">
                    <div class="bg-white dark:bg-slate-900 rounded-xl p-8 border border-gray-200 dark:border-gray-700 card-hover mb-8">
                        <h3 class="text-2xl font-bold text-gray-900 dark:text-white mb-4">How Usernames Work</h3>

                        <p class="text-gray-600 dark:text-gray-400 mb-6">
                            Usernames are <strong class="text-gray-900 dark:text-white">aliases</strong> that map to your canonical +99 identity. They make it easier to share your contact info without revealing your permanent number.
                        </p>

                        <div class="grid md:grid-cols-2 gap-6 mb-6">
                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-5 border border-gray-200 dark:border-gray-700">
                                <h4 class="font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                                    <svg class="w-5 h-5 text-green-600 dark:text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                    </svg>
                                    Username Benefits
                                </h4>
                                <ul class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
                                    <li class="flex items-start gap-2">
                                        <span class="text-green-600 dark:text-green-400">✓</span>
                                        <span>Easy to remember (@alice)</span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-green-600 dark:text-green-400">✓</span>
                                        <span>Can be changed anytime</span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-green-600 dark:text-green-400">✓</span>
                                        <span>Shareable (QR codes, links)</span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-green-600 dark:text-green-400">✓</span>
                                        <span>Keeps +99 number private</span>
                                    </li>
                                </ul>
                            </div>

                            <div class="bg-gray-50 dark:bg-slate-800 rounded-lg p-5 border border-gray-200 dark:border-gray-700">
                                <h4 class="font-bold text-gray-900 dark:text-white mb-3 flex items-center gap-2">
                                    <svg class="w-5 h-5 text-purple-600 dark:text-purple-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"/>
                                    </svg>
                                    Crypto Binding
                                </h4>
                                <ul class="space-y-2 text-sm text-gray-600 dark:text-gray-400">
                                    <li class="flex items-start gap-2">
                                        <span class="text-purple-600 dark:text-purple-400">•</span>
                                        <span>All crypto binds to +99 number</span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-purple-600 dark:text-purple-400">•</span>
                                        <span>Username changes don't affect keys</span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-purple-600 dark:text-purple-400">•</span>
                                        <span>Sessions persist across renames</span>
                                    </li>
                                    <li class="flex items-start gap-2">
                                        <span class="text-purple-600 dark:text-purple-400">•</span>
                                        <span>Server maps @username → user_id</span>
                                    </li>
                                </ul>
                            </div>
                        </div>

                        <div class="bg-gray-900 dark:bg-slate-950 rounded-xl p-6 font-mono text-sm mb-6">
                            <div class="text-xs text-gray-500 uppercase tracking-wide mb-3">Identity Resolution</div>
                            <div class="text-gray-300 mb-1">User types: <span class="text-green-400">"@alice"</span></div>
                            <div class="text-gray-500 ml-4 mb-1">↓ Server lookup</div>
                            <div class="text-gray-300 mb-1">Resolves to: <span class="text-blue-400">+99 241 772</span></div>
                            <div class="text-gray-500 ml-4 mb-1">↓ Maps to</div>
                            <div class="text-gray-300 mb-1">user_id: <span class="text-purple-400">550e8400-e29b-41d4-a716-446655440000</span></div>
                            <div class="text-gray-500 ml-4 mb-1">↓ Fetch devices</div>
                            <div class="text-gray-300">Devices: <span class="text-orange-400">[device_1, device_2, device_3]</span></div>
                        </div>

                        <div class="bg-yellow-50 dark:bg-yellow-900/20 border-l-4 border-yellow-600 dark:border-yellow-400 rounded-lg p-6">
                            <div class="flex items-start gap-3">
                                <svg class="w-5 h-5 text-yellow-600 dark:text-yellow-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
                                </svg>
                                <div>
                                    <div class="font-semibold text-yellow-900 dark:text-yellow-100 mb-1">Important</div>
                                    <p class="text-sm text-yellow-800 dark:text-yellow-200">
                                        Usernames are <strong>not</strong> part of the cryptographic identity. All session keys, signatures, and bindings use the +99 number and device_id internally. Usernames are purely for UX convenience.
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
                                <p><strong>+99 virtual numbers</strong> provide permanent identity without SIM cards or phone carriers</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>One device = one identity</strong> — each installation has independent Ed25519 + X25519 keypairs</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Multi-device support</strong> from day one with independent keys per device for security</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Prekey bundles</strong> enable asynchronous messaging without online coordination</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>SPK rotation every 30 days</strong> + OTP single-use for enhanced forward secrecy</p>
                            </div>
                        </div>

                        <div class="bg-white/10 backdrop-blur-sm rounded-xl p-6 border border-white/20">
                            <div class="flex items-start gap-3">
                                <svg class="w-6 h-6 text-green-400 flex-shrink-0 mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
                                </svg>
                                <p><strong>Usernames are aliases</strong> — all crypto binds to +99 number, not username string</p>
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
