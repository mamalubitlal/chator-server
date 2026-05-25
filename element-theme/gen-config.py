#!/usr/bin/env python3
"""Generate Element Web config.json with Chator custom theme."""
import json

config = {
    "default_server_config": {
        "m.homeserver": {
            "base_url": "http://localhost:8008",
            "server_name": "localhost"
        }
    },
    "default_theme": "light",
    "brand": "Чатор",
    "setting_defaults": {
        "custom_themes": [
            {
                "name": "Chator Blue",
                "is_dark": False,
                "colors": {
                    "accent-color": "#389cff",
                    "primary-color": "#6cb8ff",
                    "warning-color": "#ff4b55",
                    "sidebar-color": "#1a2332",
                    "roomlist-background-color": "#f0f6ff",
                    "roomlist-text-color": "#2e2f32",
                    "roomlist-text-secondary-color": "#389cff",
                    "roomlist-highlights-color": "#ffffff",
                    "roomlist-separator-color": "#d4e4ff",
                    "timeline-background-color": "#ffffff",
                    "timeline-text-color": "#2e2f32",
                    "timeline-text-secondary-color": "#61708b",
                    "timeline-highlights-color": "#f0f6ff",
                    "username-colors": ["#389cff", "#6cb8ff", "#1a7ae0", "#4da6ff", "#80c0ff"],
                    "avatar-background-colors": ["#389cff", "#6cb8ff", "#1a7ae0", "#4da6ff", "#80c0ff"]
                }
            }
        ]
    }
}

with open("/usr/share/element-web/config.json", "w") as f:
    json.dump(config, f)
