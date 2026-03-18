# чатор Element Web - Custom Branded Client

This is your custom-branded Element Web client for чатор.

## What's Customized

- **App name:** чатор (not Element)
- **Colors:** Blue & light blue theme (two themes included)
- **Default language:** Russian
- **Default country:** RU
- **Server:** Pre-configured to connect to chator.k.vu
- **Element Call:** Enabled for free voice/video calls

## Deployment Options

### Option A: Host on Render (Recommended)

1. Create a new **Static Site** on Render
2. Connect this repo
3. Set root directory: `chator/element-web`
4. Build command: (none needed - static files)
5. Publish directory: `.`
6. Add custom domain: `app.chator.k.vu` or `chat.chator.k.vu`

### Option B: Use Element's official app with custom config

Users can manually set their homeserver to `https://chator.k.vu` in the official Element app.

### Option C: Fork Element on GitHub

1. Fork https://github.com/vector-im/element-web
2. Replace `config.json` with ours
3. Add your logo to `res/img/`
4. Build and deploy

## Logo

Your logo is at `../matrix/chator-logo.png`. Convert it to SVG for best results, or rename to match the `logo` path in `config.json`.

For now, Element will show the default logo. To add yours:

1. Convert PNG to SVG (use https://vectorizer.ai)
2. Save as `chator-logo.svg` in this folder
3. Update `config.json` branding.logo path

## Mobile Apps

For custom mobile apps (iOS/Android):

1. Fork https://github.com/vector-im/element-ios (iOS)
2. Fork https://github.com/vector-im/element-android (Android)
3. Update branding in each
4. Build and publish to App Store / Google Play

**Easier alternative:** Just tell users to download Element and enter `https://chator.k.vu` as their server.

## Testing Locally

```bash
# Simple HTTP server
python3 -m http.server 8080

# Or with Node
npx serve .
```

Then open `http://localhost:8080`
