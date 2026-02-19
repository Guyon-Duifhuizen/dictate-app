<p align="center">
  <img src="icon.png" width="128" alt="DictateApp icon">
</p>

# DictateApp

Voice-to-text dictation for macOS using Google Cloud Speech. Press **Cmd+\\** to start dictating, press again to stop. Transcribed text is typed into the focused application.

## Prerequisites

- macOS 14+
- Xcode Command Line Tools (`xcode-select --install`)
- [uv](https://docs.astral.sh/uv/) (`brew install uv`)
- Google Cloud credentials with the Speech-to-Text API enabled

### Google Cloud setup

Authenticate with application default credentials:

```
gcloud auth application-default login
```

## Install

```
make install
```

This builds the Swift app and Python worker, bundles them into `DictateApp.app`, and copies it to `/Applications`.

## Launch

Open **DictateApp** from Spotlight, or:

```
open /Applications/DictateApp.app
```

On first launch, macOS will prompt for:

1. **Microphone access** -- required for audio capture
2. **Accessibility access** -- required for the global hotkey and text insertion

To start at login, either right-click the Dock icon, then Options, then Open at Login, or go to **System Settings > General > Login Items** and add DictateApp.

## Usage

| Action | Shortcut |
|---|---|
| Start/stop dictation | **Cmd+\\** |

Dictation auto-stops after 15 minutes.

## Architecture

```
+--------------------------+          +---------------------------+
|    DictateApp (Swift)    |  stdin   |  speech_worker.py (Python)|
|                          | -------> |                           |
|  Hotkey, mic capture,    |  audio   |  Decodes audio, streams   |
|  UI indicator            |  (JSON)  |  to Google Cloud Speech   |
|                          | <------- |                           |
|  Types final text into   |  stdout  |  Returns transcription    |
|  focused app             |  (JSON)  |  results                  |
+--------------------------+          +---------------------------+
```

Swift captures mic audio via `AVAudioEngine`, converts to 16kHz mono PCM, and sends base64-encoded chunks over **stdin** to the Python worker. The worker streams them to Google Cloud Speech and sends transcription results back over **stdout**. Final text is typed into the focused app via keystroke simulation.

## Development

```
make run-debug
```

## Uninstall

```
make uninstall
```
