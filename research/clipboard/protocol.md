# Clipboard experiment: what survives a chat channel

The question CQT cannot answer from here: when a message is copied out of a *rendered* chat view, does the plain-text clipboard flavor carry the **markdown source** or the **rendered appearance**? If backticks survive, protected content works in these channels. If they don't, a signer's protection silently disappears at the moment a reader copies.

## Tooling on Windows + WSL2

Use `.ignored/clipdump.ps1`, not `clipdump.sh`. The shell script's PowerShell branch pipes clipboard text back through the WSL interop bridge, and that bridge re-encodes — which is fatal here, because the whole measurement is byte-level. The `.ps1` writes the files itself, as UTF-8 with no BOM, so nothing touches the bytes between the clipboard and the file.

Two details in it are load-bearing. `-Sta` is required: the Windows clipboard API needs a single-threaded apartment and returns nothing at all without it, silently. And the output is written with an explicit `UTF8Encoding($false)` rather than `Set-Content -Encoding utf8`, because Windows PowerShell 5.1 adds a BOM — which would corrupt the exact thing we are testing.

Copy it to the Windows side and run from WSL bash or a Windows terminal, either works:

```
powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File 'C:\Users\<you>\clipdump.ps1' slack-rendered
```

Output lands in `%USERPROFILE%\clipdump`, readable from WSL at `/mnt/c/Users/<you>/clipdump`. Send me that directory.

WSLg does bridge the Windows clipboard to Linux GUI apps, so `xclip` may appear to work — I would not trust it for this. It exposes text reliably and the other flavors unreliably, and flavor enumeration is the point.

## What to run, in priority order

Do the first one first: it is the control that proves the tooling and shows what *no* transformation looks like.

1. **VS Code** — a plain text editor, so the copy should be byte-identical to the file. If it isn't, the harness is lying and nothing else is interpretable.
2. **Slack**
3. **Gmail, in a browser** — copy a *rendered* quoted reply, the indented blockquote with the vertical bar. This answers whether the `>` markers a mail client generates ever reach a human's clipboard, which decides how much the quote-prefix work buys in practice.
4. **GitHub, in a browser** — a rendered comment containing a fenced block. Markdown's home turf and the most favorable possible case for backticks surviving.
5. **Discord**
6. **WhatsApp**, then **Signal** or **Google Messages** — likely similar to each other, so two of the three is enough unless they disagree.
7. **Facebook** — no markdown at all, so the questions are URLs and line breaks.
8. **Google Docs or Word** — the README's own motivating scenario. Watch for autocorrect turning `--` into an em dash and straight quotes into curly ones *on the way in*.

Also worth one run: this repository's own spec page at `https://dhh1128.github.io/canonical-quoted-text/`, copying a fenced block out of the rendered page. That is precisely the "someone quotes a passage from a web page" scenario the algorithm exists for.

## Protocol, per app

Roughly two minutes each.

1. Copy the test message below (from this file, not from the chat UI).
2. Paste it into the app's compose box and send it to yourself or a scratch channel.
3. **Note what rendered**: did the inline span become a code chip? Did the fence become a code box? Did the `>` line become a quote bar? Write it down — this is half the data.
4. Select the *rendered* message in the transcript, copy it, and dump it as `<app>-rendered` (see Tooling above).
5. If the app offers a "copy text" / "copy message" menu item, use that too, as `<app>-copytext`. Slack and Discord both have one, and it often differs from a mouse selection.

## The test message

Everything below the line, through the closing fence. Send it as one message.

---

Ampersands & dashes -- and a "quoted" phrase with an em—dash.
Here is an inline span: `--dry-run  &  --verbose` and here is a link: https://example.test/a--b?q=1&r=2
> this line starts with a quote marker
This line is deliberately long so that a narrow window has to wrap it somewhere in the middle, which is the case that decides whether rewrapping matters.
```python
def f(x):
    return x  *  2
```

---

## What each element is testing

| element | question |
| --- | --- |
| `` `--dry-run  &  --verbose` `` | do the backticks survive a copy? do the doubled spaces inside? |
| the fenced block | do the fence lines survive? the indentation? the line endings? |
| `> this line starts…` | does the `>` survive, or did the app render a quote bar and drop it? |
| `https://example.test/a--b?q=1&r=2` | does the URL survive as text, or become display text / a shortened link? is `&` still `&`, or `&amp;`? |
| the long line | does the copy carry the author's line breaks or the window's wrapping? |
| `--`, `"…"`, `—` | does the app's autocorrect change these on send? |

## What to send back

The `clipdump` directory, plus your notes from step 3. Aggregate or raw is fine — it's a test message, there's nothing private in it.

## Why it matters

If the plain flavor keeps backticks, protected content works in chat and chop can tell users to mark values inline. If it strips them, then a value the author protected is unprotected for whoever copies it, and the failure is silent — the reader's copy canonicalizes differently and verification fails with no indication why. That decision belongs to chop's authoring guidance, and it cannot be made from measurements of email.
