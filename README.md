# My Podcasts

An Android app that logs the YouTube podcast episodes you've watched: a
rank from 1 to 10, the points you learned, and the thumbnail and title. Everything is saved right away to a
Google Sheet.

- Share an episode from the YouTube app to **My Podcasts**, **or** copy the link,
  open the app and tap **Add podcast** or Paste. Both open the same add flow.
- Add flow: link → rank (1–10) → points, one at a time. You need at least one
  point to submit.
- The list is ordered by rank (highest first). You can search, or sort by date added.
- Tap an episode to see its rank and points. From there you can open it in YouTube, edit it, or delete it.
- The Google Sheet is the source of truth. Pull down to refresh after you edit the sheet directly.

---

## 1. Create the Google Sheet and backend (one time)

1. Create a new Google Sheet, for example "My Podcasts".
2. In the sheet, open **Extensions → Apps Script**.
3. Delete the default code and paste the whole of [`apps_script/Code.gs`](apps_script/Code.gs).
4. Set your token: open **Project Settings** (gear icon) → **Script properties** → **Add script property**,
   name `TOKEN`, value your own long random secret, for example `mp-7f3k9x2q8w1z`. You'll type this into the app later.
   You can change this property at any time and it takes effect right away, with no redeploy.
   (You can also edit the `TOKEN` constant in the code instead, but then every change needs a new deployment version.)
5. Save, choose the **`setup`** function in the toolbar, and click **Run**. Grant
   the permissions it asks for. (Google warns that the app is unverified: click *Advanced →
   Go to project*.) This creates a **Podcasts** tab with these columns:

   | ID | Video ID | Title | Channel | YouTube URL | Thumbnail URL | Rank | Points | Points Count | Date Added | Last Updated |
   |---|---|---|---|---|---|---|---|---|---|---|

   You can reorder these columns or add your own. The script finds columns by their header name,
   so don't rename them.
6. Click **Deploy → New deployment**, set type to **Web app**, and choose:
   - *Execute as*: **Me**
   - *Who has access*: **Anyone**
7. Click **Deploy** and copy the **Web app URL**. It ends in `/exec`.

> If you change `Code.gs` later, go to **Deploy → Manage deployments → ✏️ Edit → Version: New version**.
> That way the same URL runs the new code. Don't use *New deployment* again, because that creates a different URL.

## 2. Build the APK with GitHub Actions

1. Create a GitHub repository (private is fine) and push this project to the `main` branch.
2. Add the signing secrets under **Settings → Secrets and variables → Actions → New repository secret**:

   | Secret | Value |
   |---|---|
   | `KEYSTORE_BASE64` | contents of `signing/keystore-base64.txt` |
   | `KEYSTORE_PASSWORD` | from `signing/signing-info.txt` |
   | `KEY_ALIAS` | from `signing/signing-info.txt` |
   | `KEY_PASSWORD` | from `signing/signing-info.txt` |

   The `signing/` folder is git-ignored. **Back it up somewhere safe.** If you lose the
   keystore, new builds can't be installed over the old app; you'd have to uninstall it first. Reinstalling is harmless because your data lives in the sheet.

   Without these secrets the workflow still builds, but it signs with a random debug key each time.
3. Every push to `main` builds the app. Open **Actions → Build APK → the latest run →
   Artifacts → my-podcasts-apk**. It downloads as a zip with the `.apk` inside.
4. To download straight from your phone, create a release tag instead:
   ```bash
   git tag v1.0.0 && git push origin v1.0.0
   ```
   The APK is attached to the release under **Releases → v1.0.0**.
   You can also run the workflow manually: **Actions → Build APK → Run workflow**.

## 3. Install on your phone

1. Download the `.apk` on the phone and open it.
2. Allow **Install unknown apps** for your browser or file manager when Android asks.
3. Open **My Podcasts → Connect sheet**, paste the Web app URL and your `TOKEN`, tap
   **Test connection**, then **Save**.

---

## Troubleshooting

**Settings → Test connection** checks the URL, the token and the sheet in one go. On success it shows
the script version, for example "Connected (script v2)".

| Message in the app | What to do |
|---|---|
| *Unauthorized: token does not match…* | The token in the app is different from the one the **deployed** script uses. Set `TOKEN` in *Script properties* (takes effect right away). If you changed the `TOKEN` constant in the code, you also need **Deploy → Manage deployments → Edit → Version: New version**. |
| *Unauthorized: TOKEN is not set in the script* | Add the `TOKEN` script property (step 1.4). |
| *The deployment is running old code* | Paste the latest `Code.gs`, then **Manage deployments → Edit → New version**. |
| *Access denied (HTTP 401/403)* or *Google asked for a sign-in* | In **Manage deployments**, set *Who has access* to **Anyone** (not "Anyone with Google account"). |
| *Script URL not found (HTTP 404)* | The deployment was deleted or archived, or the URL is wrong. Copy the `/exec` URL from **Manage deployments**. |
| *The script needs permission* | In Apps Script, run `setup` again and grant access, then deploy a new version. |
| *This is the test URL (ends with /dev)* | Use the Web app URL ending in `/exec`. URLs with `/u/1/` in them are fixed automatically. |
| *The sheet took too long to answer* / *Could not reach the sheet* | Check your connection. The app already retries once. The first request after a while can be slow because Google has to start the script. |
| *Google quota reached (HTTP 429)* | Apps Script daily limits were hit. Try again later. |

To check the backend without the app, replace `<URL>` and `<TOKEN>` in these commands:

```bash
curl -sL "<URL>?action=ping&token=<TOKEN>"
curl -sL -H 'Content-Type: text/plain' -d '{"token":"<TOKEN>","action":"list"}' "<URL>"
```

Both should print JSON starting with `{"ok":true`.

---

## Project layout

```
apps_script/Code.gs            Google Apps Script backend (list/add/update/delete/ping)
lib/main.dart                  App entry, share-intent handling
lib/models/podcast.dart        Podcast model, points <-> "1. …" text
lib/services/youtube_service.dart   Link parsing, oEmbed title lookup, thumbnails
lib/services/sheet_service.dart     HTTP client for the Apps Script web app (retries, error messages)
lib/services/settings_service.dart  Saved URL/token and offline cache
lib/services/share_service.dart     Channel to the native share receiver
lib/state/podcast_store.dart   App state (list, search, sort, CRUD)
lib/screens/                   Home, Add/Edit, Detail, Settings
android/app/src/main/kotlin/…/MainActivity.kt   Receives YouTube "Share" text
.github/workflows/build-apk.yml   CI: analyze, test, build signed APK
```

## Developing locally

Install Flutter, then run:

```bash
flutter pub get
flutter analyze
flutter test
flutter run            # with a phone connected or an emulator running
```
