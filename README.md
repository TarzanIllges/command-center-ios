# Command Center (iPhone app)

Your server's Command Center as a native, sideloaded iPhone app: full screen, stays signed in, pull to refresh, an offline screen
with "Try again", camera and microphone for Ellie, other websites open in Safari. The server address is **not** built in: the app
is pointed at your server from the server's `/iphone` page (`commandcenter://set?url=...`), so this code contains nothing private.

## How it gets to your iPhone
1. **GitHub builds it.** Every push to `main` runs `.github/workflows/build.yml` on a free GitHub Mac: XcodeGen makes the Xcode
   project from `project.yml`, Xcode compiles an unsigned `CommandCenter.ipa`, and it is published as a GitHub release.
2. **Your server hosts it.** On `/iphone`, enter this repo's name and press *Fetch the latest build*. The server downloads the
   `.ipa` to `static/ios/` and writes an AltStore source at `/static/ios/source.json`.
3. **AltStore installs it.** Add that source in AltStore on the iPhone and install *Command Center*. AltStore signs it with your
   free Apple ID; AltServer on your PC refreshes it every 7 days.

## Put it on GitHub (one time)
Create an empty repository named `command-center-ios` at github.com/new, then in this folder:

```bash
git remote add origin https://github.com/YOUR-NAME/command-center-ios.git
git push -u origin main
```

A **public** repo is simplest (unlimited free Mac builds, and the server downloads without a token; the code has nothing private).
For a **private** repo, create a fine-grained token with read access to this repo's Contents and put it on the server in
`/srv/data/tarzard/secrets/github_token` yourself.
