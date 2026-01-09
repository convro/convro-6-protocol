# Images Directory

Place your branded assets here.

## Logo Files

### Required Images

1. **banner-wide.png** (`logo/banner-wide.png`)
   - Dimensions: 1000×(100-300)px
   - Format: PNG with transparency
   - Usage: Main header logo (desktop)

2. **icon-square.png** (`logo/icon-square.png`)
   - Dimensions: 500×500px
   - Format: PNG with transparency
   - Usage: Favicon, mobile logo, footer

3. **icon-sm.png** (`logo/icon-sm.png`) [Optional]
   - Dimensions: 64×64px
   - Format: PNG
   - Usage: Smaller displays, optimized version

## Feature Badges

Place 500×500px badge images in `features/`:

- `crypto-badge.png` - Forward Secrecy feature
- `security-badge.png` - Replay Resistance feature
- `protocol-badge.png` - Authenticated Handshake
- `privacy-badge.png` - Deterministic Nonces
- `verified-badge.png` - Downgrade Resistance
- `opensource-badge.png` - Open Source badge

**Note:** If badges are missing, site falls back gracefully (hides image, shows text only).

## Screenshots

Add app screenshots to `screenshots/`:

- **Format:** PNG, JPG, JPEG, WebP, or GIF
- **Naming:** Use numbered prefixes for order (e.g., `01-chat.png`, `02-settings.png`)
- **Auto-detection:** Gallery automatically scans folder and displays all images
- **No code changes needed** - just drop files and refresh page!

### Example Structure

```
screenshots/
├── 01-login-screen.png
├── 02-chat-view.png
├── 03-contacts.png
├── 04-settings.png
└── 05-fingerprint-verify.png
```

Gallery will show "1/5", "2/5", etc. automatically.

## Image Optimization Tips

### For Web Performance

1. **Compress images:**
   ```bash
   # Use ImageOptim, TinyPNG, or:
   convert input.png -quality 85 output.png
   ```

2. **Use WebP for screenshots:**
   ```bash
   cwebp input.png -q 80 -o output.webp
   ```

3. **Responsive images** (future enhancement):
   - Create @1x, @2x, @3x versions
   - Use `srcset` attribute

### Recommended Tools

- [TinyPNG](https://tinypng.com/) - Online compression
- [ImageOptim](https://imageoptim.com/) - Mac app
- [Squoosh](https://squoosh.app/) - Web-based optimizer

---

**Current Status:** Placeholder images - replace with branded assets before deploy!
