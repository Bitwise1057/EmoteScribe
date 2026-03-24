![Game](https://img.shields.io/badge/Game-World%20of%20Warcraft-blue)
![Client](https://img.shields.io/badge/Client-Retail-important)
![Maintenance](https://img.shields.io/badge/Maintained-Yes-brightgreen)
![License](https://img.shields.io/badge/License-Apache%202.0-blue)

# EmoteScribe

EmoteScribe is a lightweight World of Warcraft addon that enhances chat readability by intelligently splitting and formatting emotes into clean, digestible segments.

Built with roleplayers and heavy emote users in mind, it keeps chat immersive without turning it into a wall of text.

This addon was largely inspired by Tammya's EmoteSplitter and uses some aspects for familiarity.

---

## Features

- Splits long emotes into readable segments
- Improves chat clarity and flow
- Lightweight with minimal performance impact
- Plug-and-play (no setup required)
- Compatible with most chat addons

---

## Installation (Release Package)

1. Go to the Releases tab on this repository
2. Download the latest .zip file
3. Extract the contents (You only need the nested EmoteScribe file, not EmoteScribe-main)
4. Move the extracted folder to your WoW AddOns directory:

`World of Warcraft/_retail_/Interface/AddOns/`

5. Verify folder structure:

AddOns/EmoteScribe/
AddOns/EmoteScribe/EmoteScribe.toc

6. Launch World of Warcraft
7. At the character select screen, click AddOns
8. Enable EmoteScribe

---

## Common Installation Mistakes

- Nested folders:
  Incorrect:
  AddOns/EmoteScribe-1.0/EmoteScribe/
  Correct:
  AddOns/EmoteScribe/

- Not extracting the .zip file
- Installing in the wrong client folder (_classic_ vs _retail_)

---

## Compatibility

- World of Warcraft Retail
- Works alongside most UI and chat addons
- No known major conflicts

---

## What It Does

EmoteScribe listens for emote-style messages and reformats them into cleaner, more readable chunks.

Instead of:
A very long emote that has to be manually typed and split to meet the maximum characters limit:

You get structured, readable output that preserves flow and intent.

<img width="609" height="151" alt="image" src="https://github.com/user-attachments/assets/7bbca1d5-d9e6-4ffb-aef1-daf09674c07f" />


---

## Contributing

Got ideas or found a bug?

- Open an Issue
- Submit a Pull Request

All contributions are welcome.

---

## License

This project is licensed under the Apache License 2.0.
