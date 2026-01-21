<?php
/**
 * Convro Website Configuration
 * All site settings, assets paths, colors, texts in one place
 */

// =============================================================================
// SITE META
// =============================================================================
define('SITE_TITLE', 'Convro 6 Protocol');
define('SITE_TAGLINE', 'Production-grade E2E encrypted messaging protocol');
define('SITE_DESCRIPTION', 'Audit-ready end-to-end encryption with authenticated prekey handshakes, per-message forward secrecy, and replay resistance. Built for security-critical applications.');
define('SITE_URL', 'https://convro.eu');
define('SITE_KEYWORDS', 'encryption, e2e, cryptography, messaging protocol, security, privacy, open source');

// =============================================================================
// ASSETS PATHS
// =============================================================================

// Base paths
define('ASSETS_PATH', '/assets');
define('IMAGES_PATH', ASSETS_PATH . '/images');
define('CSS_PATH', ASSETS_PATH . '/css');
define('JS_PATH', ASSETS_PATH . '/js');

// Logo & Branding
define('LOGO_BANNER_WIDE', IMAGES_PATH . '/logo/banner-wide.png');  // 1000x(100-300)
define('LOGO_ICON_SQUARE', IMAGES_PATH . '/logo/icon-square.png');  // 500x500
define('LOGO_ICON_SM', IMAGES_PATH . '/logo/icon-sm.png');          // 64x64 (for mobile)

// Feature Badges (500x500)
define('BADGE_CRYPTO', IMAGES_PATH . '/features/crypto-badge.png');
define('BADGE_SECURITY', IMAGES_PATH . '/features/security-badge.png');
define('BADGE_PROTOCOL', IMAGES_PATH . '/features/protocol-badge.png');
define('BADGE_PRIVACY', IMAGES_PATH . '/features/privacy-badge.png');
define('BADGE_VERIFIED', IMAGES_PATH . '/features/verified-badge.png');
define('BADGE_OPENSOURCE', IMAGES_PATH . '/features/opensource-badge.png');

// Screenshots folder (dynamic)
define('SCREENSHOTS_DIR', __DIR__ . '/../assets/images/screenshots/');
define('SCREENSHOTS_PATH', IMAGES_PATH . '/screenshots/');

// =============================================================================
// EXTERNAL LINKS
// =============================================================================
define('GITHUB_REPO', 'https://github.com/convro/convro-6-protocol');
define('GITHUB_API_RUNS', 'https://api.github.com/repos/convro/convro-6-protocol/actions/runs');
define('DOCS_URL', SITE_URL . '/docs');
define('THREAT_MODEL_PDF', SITE_URL . '/docs/threat-model/C6P-Threat-Model-CONCISE.pdf');
define('THREAT_MODEL_AUDIT_PDF', SITE_URL . '/docs/threat-model/C6P-Threat-Model-v1-AUDIT.pdf');
define('API_DOCS_URL', SITE_URL . '/api');
define('TEST_VECTORS_URL', SITE_URL . '/docs/crypto/test-vectors/v1');

// Social
define('DISCORD_URL', '#'); // TBD
define('TWITTER_URL', '#'); // TBD
define('SECURITY_EMAIL', 'security@convro.eu');

// =============================================================================
// PROTOCOL STATS (Updated from CI/CD)
// =============================================================================
define('TESTS_TOTAL', '109');
define('TESTS_PASSING', '109');
define('CI_JOBS_TOTAL', '9');
define('CI_JOBS_PASSING', '9');
define('CLIPPY_WARNINGS', '0');
define('MSRV', '1.85.0');

// =============================================================================
// FEATURE HIGHLIGHTS
// =============================================================================
$FEATURES = [
    [
        'badge' => BADGE_CRYPTO,
        'title' => 'Forward Secrecy',
        'description' => 'Per-message keys with symmetric ratcheting. Compromise of current state does not reveal past messages.',
        'spec_link' => '/docs/Sessions/dm-ratchet-state-machine.md',
        'spec_cite' => '§ Sessions/DM-Ratchet'
    ],
    [
        'badge' => BADGE_SECURITY,
        'title' => 'Replay Resistance',
        'description' => 'Consumed counter sets with bounded skip-window (2048 messages). Duplicate messages rejected immediately.',
        'spec_link' => '/docs/crypto/c6p-replay-and-skip-window.md',
        'spec_cite' => '§ Crypto/Replay-Protection'
    ],
    [
        'badge' => BADGE_PROTOCOL,
        'title' => 'Authenticated Handshake',
        'description' => 'IslandAccord v1 with 3DH + optional 4DH (OTP). Mutual authentication via Ed25519 signatures.',
        'spec_link' => '/docs/handshake/island-accord-crypto.md',
        'spec_cite' => '§ Handshake/IslandAccord'
    ],
    [
        'badge' => BADGE_PRIVACY,
        'title' => 'Deterministic Nonces',
        'description' => 'No RNG dependency for AEAD nonces. Safety-analyzed, fail-closed design.',
        'spec_link' => '/docs/crypto/c6p-nonce-policy.md',
        'spec_cite' => '§ Crypto/Nonce-Policy'
    ],
    [
        'badge' => BADGE_VERIFIED,
        'title' => 'Downgrade Resistance',
        'description' => 'Protocol version and suite ID bound in AAD. Transcript hash prevents version rollback.',
        'spec_link' => '/docs/crypto/c6p-aead-and-aad.md',
        'spec_cite' => '§ Crypto/AAD-Construction'
    ],
    [
        'badge' => BADGE_OPENSOURCE,
        'title' => 'Open Source',
        'description' => 'Complete reference implementation in Rust. Dual licensed Apache 2.0 / MIT.',
        'spec_link' => GITHUB_REPO,
        'spec_cite' => 'GitHub Repository'
    ]
];

// =============================================================================
// THREAT MODEL HIGHLIGHTS
// =============================================================================
$THREATS = [
    [
        'id' => 1,
        'category' => 'Handshake',
        'title' => 'Man-in-the-Middle Attack',
        'status' => 'Mitigated',
        'mitigation' => 'SPK signatures + Key Confirmation (KC1/KC2)'
    ],
    [
        'id' => 6,
        'category' => 'OTP',
        'title' => 'Server Rotation Attack',
        'status' => 'Mitigated',
        'mitigation' => 'OTP consumed immediately, cryptographic binding'
    ],
    [
        'id' => 10,
        'category' => 'State Machine',
        'title' => 'Race Condition',
        'status' => 'Mitigated',
        'mitigation' => 'Atomic state transitions, fail-closed design'
    ],
    [
        'id' => 13,
        'category' => 'Transport',
        'title' => 'Message Injection',
        'status' => 'Mitigated',
        'mitigation' => 'AEAD authentication, session binding in AAD'
    ],
    [
        'id' => 14,
        'category' => 'Transport',
        'title' => 'Message Duplication',
        'status' => 'Mitigated',
        'mitigation' => 'Consumed counter set, replay detection'
    ]
];

// =============================================================================
// FAQ
// =============================================================================
$FAQ = [
    [
        'question' => 'Is C6P ready for production use?',
        'answer' => 'Yes. The Rust reference implementation is complete with 109/109 tests passing, zero clippy warnings, and comprehensive documentation. The protocol is ready for external cryptographic audit.'
    ],
    [
        'question' => 'How does C6P differ from Signal Protocol?',
        'answer' => 'C6P uses deterministic nonces (no RNG dependency), symmetric ratcheting only (simpler state), and a different handshake (IslandAccord v1 with 3DH+OTP). Both provide forward secrecy and replay resistance.'
    ],
    [
        'question' => 'What platforms are supported?',
        'answer' => 'Currently: Rust (production-ready). Planned: Swift (iOS), Kotlin (Android), desktop/web. All implementations must pass identical test vectors.'
    ],
    [
        'question' => 'Has C6P been audited?',
        'answer' => 'Not yet. The protocol is audit-ready with comprehensive threat models, test vectors, and documentation. External cryptographic audit is planned.'
    ],
    [
        'question' => 'Can I use C6P in commercial projects?',
        'answer' => 'Yes. C6P is dual-licensed under Apache 2.0 / MIT. Choose whichever license works best for your use case.'
    ],
    [
        'question' => 'How do I report security vulnerabilities?',
        'answer' => 'Email ' . SECURITY_EMAIL . ' (do not open public issues). We aim to respond within 48 hours.'
    ]
];

// =============================================================================
// NAVIGATION
// =============================================================================
$NAV_ITEMS = [
    ['label' => 'Protocol', 'href' => '#protocol'],
    ['label' => 'Security', 'href' => '#security'],
    ['label' => 'Implementation', 'href' => '#implementation'],
    ['label' => 'Threat Model', 'href' => '#threat-model'],
    ['label' => 'Documentation', 'href' => DOCS_URL],
    ['label' => 'GitHub', 'href' => GITHUB_REPO, 'external' => true]
];

// =============================================================================
// CACHE SETTINGS
// =============================================================================
define('CACHE_DIR', __DIR__ . '/../cache/');
define('CACHE_TTL', 300); // 5 minutes

// Create cache dir if not exists
if (!is_dir(CACHE_DIR)) {
    mkdir(CACHE_DIR, 0755, true);
}
