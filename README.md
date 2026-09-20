
<p align="center">
  <a href="https://github.com/ashcodex505/grammar-extension" target="_blank">
    <img height="150" alt="Cotabby Extended red logo" src="Cotabby/Assets.xcassets/AppIconDev.appiconset/1024.png" />
  </a>
</p>

<h1 align="center">Cotabby Extended [beta]</h1>

<p align="center"><em>Personal, learning autocorrection and local-first AI autocomplete for macOS.</em></p>

<p align="center">
  Extended and maintained by <a href="https://github.com/ashcodex505"><strong>Ashish Kurse</strong></a>.
</p>

<p align="center">
  Based on <a href="https://github.com/FuJacob/cotabby">the original Cotabby project by FuJacob and contributors</a>.
</p>

<p align="center">
  <a href="https://github.com/ashcodex505/grammar-extension/actions/workflows/build.yml"><img alt="Build" src="https://img.shields.io/github/actions/workflow/status/ashcodex505/grammar-extension/build.yml?branch=main" /></a>
  <a href="LICENSE"><img alt="License: AGPL v3" src="https://img.shields.io/badge/license-AGPL--3.0-blue.svg" /></a>
  <a href="https://github.com/ashcodex505/grammar-extension/stargazers"><img alt="Stars" src="https://img.shields.io/github/stars/ashcodex505/grammar-extension?style=flat" /></a>
  <img alt="Swift" src="https://img.shields.io/badge/Swift-F05138?logo=swift&amp;logoColor=white" />
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey" />
</p>

<p align="center">
  <sub>This fork keeps Cotabby's original autocomplete experience and adds a user-owned autocorrection system focused on control, learning, privacy, and safe reversal.</sub>
</p>

---

## What This Fork Adds

The original Cotabby provides the menu-bar app, Accessibility integration, inline suggestion UI,
Apple Intelligence support, downloadable local-model runtime, and deterministic spell-checking
foundation. Ashish Kurse built on that foundation with a personal autocorrection layer that runs
before the generic spell checker.

- **Editable personal replacements** — add typo-to-correction rules directly in Settings, including
  valid words (`form` → `from`), contractions (`im` → `I'm`), single letters (`u` → `you`), names,
  and multi-word phrases (`get chat` → `this chat`).
- **Quick correction capture** — select a misspelled word or phrase anywhere, press
  **Control–Shift–`**, enter the replacement, and Cotabby saves or updates the automatic rule.
- **74 starter corrections** — the supplied typo list is installed as editable rules on first launch.
- **Personal vocabulary** — teach Cotabby words it must accept, with optional synchronization to the
  macOS learned-word dictionary.
- **Flexible imports** — preview and import JSON, CSV, TSV, Markdown-style lists, `word:replacement`,
  and `word -> replacement` files, with warnings and conflict detection before anything changes.
- **Import macOS replacements** — bring existing system text replacements into Cotabby.
- **Local learning** — accepted corrections progress from observed, to suggestion-only, to trusted;
  repeatedly reverted candidates become blocked for that application.
- **Immediate Backspace undo** — reverse an automatic correction only when the app, field, focus
  generation, and adjacent corrected text still match, preventing stale edits in another field.
- **Complete backups** — export and restore rules, vocabulary, and learning history as versioned JSON.
- **Fast and private matching** — the typing path uses an immutable in-memory index and stores only
  correction pairs and counters, never the surrounding sentences.

Explicit personal rules take priority, followed by trusted learned corrections, SymSpell, and the
macOS spell checker. Longest matching phrases win, and all automatic changes happen only at a
committed word boundary.

## What It Does

Cotabby adds AI autocomplete to almost any text field on your Mac. As you type, a gray suggestion appears inline next to your cursor. Press `Tab` to accept it a word at a time, or keep typing to ignore it.

The default Apple Intelligence and Open Source engines run on your Mac. No account or telemetry is
required. An optional OpenAI-compatible engine can connect to a server you configure.

## Demo

<p align="center">
  <a href="https://www.youtube.com/watch?v=p3TIgxQFQGE"><strong>Watch on YouTube →</strong></a>
</p>

<div align="center">

|  |  |
|:---:|:---:|
| <img src="gifs/slack.gif" alt="Cotabby emoji autocomplete demo" width="400" height="225" /> | <img src="gifs/imessage.gif" alt="Cotabby autocomplete demo" width="400" height="225" /> |
| <img src="gifs/autocorrect.gif" alt="Cotabby autocorrect demo" width="400" height="225" /> | <img src="gifs/macros.gif" alt="Cotabby inline macros demo" width="400" height="225" /> |

</div>

## Features

- **Ghost-text autocomplete** — AI suggestions inline in almost any macOS text field; `Tab` accepts a word at a time
- **Emoji autocomplete** — type `:rocket:` and accept it without leaving the field
- **Inline macros** — type `/` for quick math, unit and currency conversion, dates, and random values
- **Personal autocorrect** — create exact word or phrase replacements that run before generic spelling
- **Selection-to-rule shortcut** — press **Control–Shift–`** after selecting text to add its correction
- **Learning corrections** — repeated acceptance raises confidence while Backspace reversals lower it
- **Personal vocabulary** — keep names, product terms, and deliberate spellings from being corrected
- **One-key correction** — accept an offered spelling fix with a single keystroke

## Privacy

Privacy is the whole point, so Cotabby's default engines keep generation on your Mac:

- Apple Intelligence and Open Source generation run on-device.
- The optional OpenAI-compatible engine sends a bounded request only to the endpoint you configure;
  that endpoint can be loopback, on your local network, or a public HTTPS service.
- No analytics, no telemetry, no crash reporting.
- A normal install never writes what you type to disk.
- Apart from a configured endpoint, the network is used for model downloads and update checks, not
  suggestion generation.

## Engines

Cotabby generates suggestions in three ways. You choose which in Settings → Engine:

- **Apple Intelligence** — Apple's model, built into macOS 26 or later on supported Macs. Nothing to download.
- **Open Source** — a small AI model you download that runs entirely on your Mac. Works on any supported Mac (macOS 14+), with or without Apple Intelligence.
- **OpenAI-compatible** — a completion or chat endpoint you configure, including local Ollama,
  another LAN host, or a public HTTPS service. Endpoint credentials are stored in Keychain.

If your Mac supports Apple Intelligence, that's the easiest place to start. Otherwise, use the Open Source engine and pick one of the built-in models:

| Model          | Size    | Good for                          |
| -------------- | ------- | --------------------------------- |
| `tabby-2-nano` | ~0.8 GB | Older or low-memory Macs; fastest |
| `tabby-2-mini` | ~1.4 GB | A solid everyday balance          |
| `tabby-2-base` | ~4.5 GB | Higher-quality suggestions        |
| `tabby-2-pro`  | ~5.0 GB | Best quality                      |

Download any of them straight from Cotabby's menu bar.

<details>
<summary><strong>Advanced:</strong> model files, custom models, and how generation works</summary>

<br />

Under the hood, the Open Source engine runs local GGUF *base* models in-process through [llama.cpp](https://github.com/ggerganov/llama.cpp) (via [CotabbyInference](https://github.com/FuJacob/cotabbyinference)). Instead of prompting an instruction-tuned chat model, Cotabby treats the model as a pure text continuer and conditions it on your name, writing style, language, and on-screen context.

| Model          | File                             | Size    | Source                                                                       |
| -------------- | -------------------------------- | ------- | ---------------------------------------------------------------------------- |
| `tabby-2-nano` | `Qwen3.5-0.8B-Base.i1-Q6_K.gguf` | ~0.8 GB | [Hugging Face](https://huggingface.co/mradermacher/Qwen3.5-0.8B-Base-i1-GGUF) |
| `tabby-2-mini` | `Qwen3.5-2B-Base.i1-Q4_K_M.gguf` | ~1.4 GB | [Hugging Face](https://huggingface.co/mradermacher/Qwen3.5-2B-Base-i1-GGUF)   |
| `tabby-2-base` | `gemma-4-E2B.i1-Q6_K.gguf`       | ~4.5 GB | [Hugging Face](https://huggingface.co/mradermacher/gemma-4-E2B-i1-GGUF)       |
| `tabby-2-pro`  | `gemma-4-E4B.i1-Q4_K_M.gguf`     | ~5.0 GB | [Hugging Face](https://huggingface.co/mradermacher/gemma-4-E4B-i1-GGUF)       |

**Bring your own model.** Any GGUF small enough to run on-device works. Drop a `.gguf` file into Cotabby's models folder and refresh the model list from the menu bar. Browse the [unsloth GGUF collection](https://huggingface.co/unsloth) for more variants — smaller quants (`Q3_K_M`, `Q4_K_S`) trade quality for size; larger models give better completions at the cost of memory and per-token latency.

For the full suggestion pipeline, see [ARCHITECTURE.md](ARCHITECTURE.md).

</details>

## Build and Run This Fork

**Compatibility:** macOS 14.0 or later. The Apple Intelligence engine needs macOS 26 or later on a supported Mac; on older systems, use the Open Source engine.

Clone Ashish's repository and build the separate red `Cotabby Dev` application:

```bash
git clone https://github.com/ashcodex505/grammar-extension.git
cd grammar-extension
open Cotabby.xcodeproj
```

In Xcode, select the **Cotabby Dev** scheme and your Mac as the destination, then build and run.
The red development identity is separate from the original blue Cotabby app, so macOS keeps its
Accessibility and Input Monitoring permissions separate.

For a command-line development build:

```bash
./scripts/build_and_run.sh --verify
```

The original Cotabby release and Homebrew package remain available from
[FuJacob/cotabby](https://github.com/FuJacob/cotabby). Those install the upstream blue app, not the
extended red development build in this repository.

## Using Cotabby

Start typing in almost any text field. When a gray suggestion appears:

- **`Tab`** — accept the next word. (Prefer whole phrases? Switch this in Settings → Acceptance Mode.)
- **`` ` `` (backtick)** — accept the entire suggestion at once.
- **Control–Shift–`` ` ``** — turn the selected word or phrase into a personal correction rule.
- **`Esc`**, or just keep typing — dismiss it.

Suggestion-acceptance shortcuts are rebindable under Settings → Shortcuts. The quick-correction
capture shortcut is fixed so it remains predictable across applications.

## Permissions

Cotabby works inside other apps, so macOS asks for a few permissions. Each one maps to a specific feature, and Cotabby walks you through them on first launch:

- **Accessibility** — read the text and cursor position in the field you're typing in, and insert what you accept.
- **Input Monitoring** — notice your typing so it knows when to suggest, and detect the accept keys.
- **Screen Recording** *(optional)* — capture the area around your cursor for visual context. Leave it off and everything else still works.

Cotabby blocks generation, presentation, and insertion in password and other secure fields.

## Local Development

Requires Xcode and Command Line Tools. Apple Silicon is strongly recommended for local model performance. For setup, build, test, and contribution workflow details, start with [CONTRIBUTING.md](CONTRIBUTING.md).

```bash
git clone https://github.com/ashcodex505/grammar-extension.git
cd grammar-extension
open Cotabby.xcodeproj
```

If you want to understand the runtime and suggestion pipeline before contributing, read [ARCHITECTURE.md](ARCHITECTURE.md).

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, build, and PR guidelines, and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community expectations. For a tour of the runtime and suggestion pipeline, read [ARCHITECTURE.md](ARCHITECTURE.md).

## Acknowledgments

- [FuJacob/cotabby](https://github.com/FuJacob/cotabby) and its maintainers for the original app,
  architecture, macOS integration, autocomplete pipeline, model runtime, and design this fork builds on.
- [llama.cpp](https://github.com/ggerganov/llama.cpp), [CotabbyInference](https://github.com/FuJacob/cotabbyinference), [Sparkle](https://github.com/sparkle-project/Sparkle), and [swift-log](https://github.com/apple/swift-log) for runtime, updates, and logging.
- Apple's FoundationModels, Accessibility, SwiftUI, and AppKit for on-device generation and macOS integration.
- [GitHub gemoji](https://github.com/github/gemoji) and Hugging Face for the emoji data and downloadable models.
- [SymSpell](https://github.com/wolfgarbe/SymSpell) by Wolf Garbe (MIT) for multilingual autocorrect; frequency dictionaries derive from [Google Ngrams](https://books.google.com/ngrams) (CC BY 3.0) and licensed SCOWL/Hunspell word lists.
- Everyone who filed issues, tested prereleases, and sent pull requests.

## Created by

**Cotabby Extended** is developed and maintained by
<a href="https://github.com/ashcodex505">Ashish Kurse (@ashcodex505)</a>.

It is a derivative of the original
<a href="https://github.com/FuJacob/cotabby">Cotabby</a>, created by
<a href="https://github.com/FuJacob">@FuJacob</a> and developed with
<a href="https://github.com/jam-cai">@jam-cai</a> and
<a href="https://github.com/akramj13">@akramj13</a>. This fork preserves that attribution while
documenting Ashish's personal dictionary, import/export, safe undo, and local-learning additions.

## License

Cotabby is licensed under the [GNU Affero General Public License v3.0](LICENSE). You can use, study, modify, and redistribute the app, but if you distribute a modified version or make one available to users over a network, you must provide the corresponding source code under the same license.

Third-party dependencies, emoji data, and downloadable model weights keep their own licenses and usage terms. Bundled third-party notices (SymSpell and the autocorrect frequency dictionary) are reproduced in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
