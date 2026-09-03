# Yazar

<img width="500" alt="yazar_intro" src="https://github.com/user-attachments/assets/0593fad3-8aae-40b9-a3cf-3b86097bd94e" />


Yazar is a focused macOS app that does one thing well: speech to text.

I built it because the options I found were heavy Electron apps, paid, or both. Yazar is lightweight, native, launches instantly, and disappears when you're done.

## Features

- Hold-to-record dictation from anywhere in macOS
- Configurable dictation key: any modifier, or a pair of them
- Automatic text insertion into the active app, with every transcription kept on the clipboard
- Context-aware capitalization, punctuation, and spacing around the caret or selection
- On-device transcription with Apple Speech
- Configurable OpenRouter transcription models
- Automatic provider and model routing by the selected keyboard input source
- Selectable transcription language and provider
- Selectable audio input and status sound themes
- OpenRouter API keys stored in the macOS Keychain

## Usage

Yazar runs in the menu bar.

- Hold the dictation key to record. It is 🌐 Globe until you change it in Settings → Dictation, where you can pick any modifier or a pair such as ⌃⌥.
- Release it to transcribe and paste the text.
- Press Escape while recording or transcribing to cancel.
- Use the menu bar icon to change the dictation key, transcription provider, model, language, microphone, or sounds.
- In Settings → Transcription, enable Model Routing to choose a provider and model for each keyboard input source configured on your Mac. Yazar then uses the selected source's intended language for each dictation.

Yazar reads the active text field through macOS Accessibility and fits each transcription to the current caret or selection before pressing ⌘V. If the target does not expose its text context, Yazar pastes the original transcription unchanged. Every transcription still reaches the clipboard, so it remains available when the active app does not accept the synthetic shortcut.

Apple Speech processes recordings on your Mac. macOS may download the selected language asset into system storage the first time you use it and manages later model updates. Yazar does not write dictation recordings to disk. Meeting capture writes its audio to disk while it is still needed for transcription and removes it after transcription succeeds.

When you select OpenRouter, Yazar sends each recording directly to OpenRouter for transcription. Your API key stays in the macOS Keychain.


## Requirements

- macOS 26.5 or later
- An [OpenRouter](https://openrouter.ai/) API key if you use the OpenRouter provider

## Build from source

1. Clone the repository.
2. Open `yazar.xcodeproj` in Xcode.
3. Select the `yazar` scheme and run the app.
4. Choose Apple Speech or OpenRouter in Yazar Settings. Enter an OpenRouter API key if needed.
5. Grant Microphone and Accessibility access when prompted.
6. If you keep the default 🌐 Globe dictation key, open System Settings → Keyboard and set “Press 🌐 key to” to “Do Nothing.” Choosing any other key in Yazar Settings → Dictation skips this step.

## Contributing

Bug reports and focused pull requests are welcome. For larger changes, open an issue first so the approach can be discussed before implementation.
