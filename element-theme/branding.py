#!/usr/bin/env python3
"""Apply Chator branding to Element Web and Element Call deployments.

Called by deploy.sh after extracting Element Web/Call tarballs.
Changes: tab title, favicon, app name, OG tags, and logo alt text.
"""
import os, re, shutil

EW = "/usr/share/element-web"
EC = "/usr/share/element-call"
LOGO = os.path.join(EW, "themes/element/img/logos/chator-logo.png")

# --- Element Web ---
idx = os.path.join(EW, "index.html")
if os.path.exists(idx):
    with open(idx, "r") as f:
        html = f.read()

    html = re.sub(r"<title>Element</title>", "<title>Чатор</title>", html)
    html = re.sub(
        r"apple-mobile-web-app-title content='Element'",
        "apple-mobile-web-app-title content='Чатор'",
        html,
    )
    html = re.sub(
        r"application-name content='Element'",
        "application-name content='Чатор'",
        html,
    )
    html = re.sub(
        r"href='vector-icons/favicon[^']*\.ico'",
        "href='chator-logo.png'",
        html,
    )

    with open(idx, "w") as f:
        f.write(html)
    print("Element Web branded")

    # Copy logo to root for favicon use
    if os.path.exists(LOGO):
        shutil.copy(LOGO, os.path.join(EW, "chator-logo.png"))

# --- Element Call ---
idx = os.path.join(EC, "index.html")
if os.path.exists(idx):
    with open(idx, "r") as f:
        html = f.read()

    html = re.sub(
        r"<title>Element Call</title>",
        "<title>Чатор</title>",
        html,
    )
    html = re.sub(
        r"og:title content='Element Call",
        "og:title content='Чатор",
        html,
    )
    html = re.sub(
        r"og:description content='[^']*'",
        "og:description content='Присоединяйтесь к звонку в Чатор'",
        html,
    )

    with open(idx, "w") as f:
        f.write(html)
    print("Element Call HTML branded")

    # Replace favicon
    if os.path.exists(LOGO):
        shutil.copy(LOGO, os.path.join(EC, "favicon.png"))
        print("Element Call favicon replaced")

    # Fix translation files and JS bundles
    assets_dir = os.path.join(EC, "assets")
    if os.path.isdir(assets_dir):
        for fname in os.listdir(assets_dir):
            path = os.path.join(assets_dir, fname)
            if not os.path.isfile(path):
                continue
            is_json = fname.endswith(".json") and "-app-" in fname
            is_js = fname.startswith("index-") and fname.endswith(".js")
            if not (is_json or is_js):
                continue
            with open(path, "r", encoding="utf-8") as f:
                content = f.read()
            new = content.replace("Element Call", "Чатор")
            new = new.replace("(Beta)", "")
            if new != content:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(new)
                print(f"  Patched: {fname}")

    # Add cache-busting v=1 to asset URLs in HTML (fresh on every deploy)
    with open(idx, "r") as f:
        html = f.read()
    html = re.sub(r'(src="[^"]+\.js)(")', r'\1?v=1\2', html)
    html = re.sub(r'(href="[^"]+\.css)(")', r'\1?v=1\2', html)
    html = re.sub(r'(href="[^"]+_sentry[^"]+\.js)(")', r'\1?v=1\2', html)
    with open(idx, "w") as f:
        f.write(html)
    print("Element Call cache-busting added")
