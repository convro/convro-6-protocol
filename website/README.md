# Convro Website

Production-ready website for Convro 6 Protocol. Built with PHP, Tailwind CSS, and Alpine.js.

## Features

- ✅ **Fully Responsive** - Mobile-first design, works on all devices
- ✅ **Dark/Light Mode** - System preference detection + manual toggle
- ✅ **Live CI/CD Status** - Real-time GitHub Actions status with caching
- ✅ **Dynamic Screenshot Gallery** - Auto-scans folder, carousel with keyboard nav
- ✅ **Zero Build Step** - Plain PHP + CDN, deploy anywhere
- ✅ **SEO Optimized** - Meta tags, Open Graph, Twitter Cards
- ✅ **Performance** - Minimal JS, lazy loading, optimized images

## Quick Start

### Local Development

1. **Requirements:**
   - PHP 7.4+ (with `curl` extension)
   - Web server (Apache, Nginx, or PHP built-in)

2. **Run locally:**
   ```bash
   cd website
   php -S localhost:8000
   ```

3. **Open in browser:**
   ```
   http://localhost:8000
   ```

### CloudPanel Deployment

1. **Upload files:**
   ```bash
   # SSH to VPS
   ssh user@your-vps

   # Copy website files to htdocs
   cp -r /path/to/website/* /home/convro/htdocs/convro.eu/
   ```

2. **Set permissions:**
   ```bash
   chmod 755 /home/convro/htdocs/convro.eu
   chmod 777 /home/convro/htdocs/convro.eu/cache  # Cache directory writable
   ```

3. **Configure domain:**
   - CloudPanel → Sites → convro.eu
   - Document Root: `/home/convro/htdocs/convro.eu`
   - PHP Version: 8.0+
   - SSL: Auto (Let's Encrypt)

4. **Nginx config** (CloudPanel auto-generates, but verify):
   ```nginx
   location / {
       try_files $uri $uri/ /index.php?$args;
   }

   location ~ \.php$ {
       fastcgi_pass unix:/var/run/php/php8.0-fpm.sock;
       fastcgi_index index.php;
       include fastcgi_params;
   }
   ```

## Configuration

All site configuration in `includes/config.php`:

### Key Constants

```php
// Site Meta
define('SITE_TITLE', 'Convro 6 Protocol');
define('SITE_URL', 'https://convro.eu');

// Assets (update paths if needed)
define('LOGO_BANNER_WIDE', '/assets/images/logo/banner-wide.png');
define('LOGO_ICON_SQUARE', '/assets/images/logo/icon-square.png');

// External Links
define('GITHUB_REPO', 'https://github.com/convro/convro-6-protocol');
define('SECURITY_EMAIL', 'security@convro.eu');

// Cache
define('CACHE_TTL', 300); // 5 minutes
```

### Add Your Logos

Replace placeholder images:

1. **Wide Banner** (1000×100-300px):
   ```bash
   cp your-banner.png assets/images/logo/banner-wide.png
   ```

2. **Square Icon** (500×500px):
   ```bash
   cp your-icon.png assets/images/logo/icon-square.png
   ```

3. **Feature Badges** (500×500px each):
   ```bash
   cp crypto-badge.png assets/images/features/
   cp security-badge.png assets/images/features/
   # etc...
   ```

### Add Screenshots

Just drop files into `assets/images/screenshots/` - the gallery auto-detects them:

```bash
cp screenshot-1.png assets/images/screenshots/
cp screenshot-2.png assets/images/screenshots/
# Gallery automatically shows all images in folder
```

**Supported formats:** PNG, JPG, JPEG, WebP, GIF

**Sorting:** Files sorted alphabetically by filename (use `01-`, `02-` prefix for order)

## Directory Structure

```
website/
├── index.php                   # Main page
├── includes/
│   ├── config.php             # All configuration (edit this!)
│   └── functions.php          # Helper functions
├── components/
│   ├── header.php             # Navigation + logo
│   ├── footer.php             # Footer links
│   ├── hero.php               # Hero section
│   └── screenshot-gallery.php # Dynamic gallery
├── assets/
│   ├── css/
│   │   └── custom.css         # Custom styles
│   ├── js/
│   │   └── app.js             # Alpine.js interactions
│   └── images/
│       ├── logo/              # Your logos here
│       ├── features/          # Feature badges
│       └── screenshots/       # App screenshots (auto-scanned)
└── cache/                     # Auto-generated (gitignored)
```

## Features

### Live GitHub Status

Fetches CI/CD status from GitHub API with 5-minute caching:

```php
// In includes/functions.php
function getGitHubStatus() {
    // Returns: status, conclusion, updated_at, tests, warnings
}
```

Cache file: `cache/github-status.json` (auto-generated)

### Dynamic Screenshot Gallery

Gallery automatically scans `assets/images/screenshots/` and displays all images:

- **Navigation:** Arrow keys, click arrows, or thumbnails
- **Counter:** Shows "3/17" current position
- **Responsive:** Mobile swipe support (via Alpine.js)
- **Lazy Load:** Images loaded on demand

**Add more screenshots:** Just drop files in folder, no code changes needed!

### Dark/Light Mode

Automatic system preference detection + manual toggle:

- Saves preference to `localStorage`
- Smooth transitions
- All colors use CSS variables
- Toggle button in header

### SEO & Meta Tags

Generated dynamically in `includes/functions.php`:

```php
generateMetaTags($title, $description);
// Outputs: title, description, OG tags, Twitter Cards
```

## Customization

### Colors

Edit theme colors in `tailwind.config` (index.php):

```javascript
tailwind.config = {
    darkMode: 'class',
    theme: {
        extend: {
            colors: {
                // Add custom colors here
            }
        }
    }
}
```

### Fonts

Current: Inter (sans) + JetBrains Mono (code)

Change in `<head>`:

```html
<link href="https://fonts.googleapis.com/css2?family=YOUR_FONT&display=swap" rel="stylesheet">
```

### Sections

All sections in `index.php`. To add/remove:

1. Comment out section
2. Or copy/paste section blocks
3. Update navigation in `includes/config.php` (`$NAV_ITEMS`)

## Performance

### Optimizations

- ✅ Tailwind CSS CDN (no build step)
- ✅ Alpine.js CDN (minimal JS, ~15KB gzipped)
- ✅ Image lazy loading
- ✅ GitHub API caching (5 min TTL)
- ✅ No jQuery or heavy frameworks

### Caching

GitHub API responses cached in `cache/github-status.json`:

- **TTL:** 5 minutes (configurable in `config.php`)
- **Auto-refresh:** On cache expiry
- **Fallback:** Shows static data if API fails

Clear cache:

```bash
rm cache/github-status.json
```

## Troubleshooting

### Cache Permission Errors

```bash
chmod 777 website/cache
```

### GitHub API Rate Limit

Unauthenticated requests: 60/hour per IP.

**Solution:** Add GitHub token (optional):

```php
// In includes/functions.php, add header:
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Authorization: Bearer YOUR_GITHUB_TOKEN'
]);
```

### Screenshots Not Showing

Check:

1. File permissions: `chmod 644 assets/images/screenshots/*.png`
2. File format: Must be PNG/JPG/JPEG/WebP/GIF
3. File path: Must be in `assets/images/screenshots/`

### PHP Version Issues

Requires PHP 7.4+ for:
- Arrow functions (`fn()`)
- Null coalescing operator (`??`)
- Array spread (`...`)

## Browser Support

- Chrome/Edge: Latest 2 versions
- Firefox: Latest 2 versions
- Safari: Latest 2 versions
- Mobile: iOS Safari 12+, Android Chrome 90+

## License

Same as main repository: Apache 2.0 / MIT dual license

## Credits

- **Framework:** PHP (vanilla, no framework)
- **CSS:** Tailwind CSS 3.x (CDN)
- **JS:** Alpine.js 3.x (CDN)
- **Fonts:** Inter, JetBrains Mono (Google Fonts)
- **Icons:** Heroicons (inline SVG)

---

**Need help?** Check main repo README or open an issue on GitHub.
