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
4. At the top of the script, change `TOKEN` to your own long random secret, for example
   `mp-7f3k9x2q8w1z`. You'll type this into the app later.
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
> That way the same URL runs the new code.

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

## Project layout

```
apps_script/Code.gs            Google Apps Script backend (list/add/update/delete)
lib/main.dart                  App entry, share-intent handling
lib/models/podcast.dart        Podcast model, points <-> "1. …" text
lib/services/youtube_service.dart   Link parsing, oEmbed title lookup, thumbnails
lib/services/sheet_service.dart     HTTP client for the Apps Script web app
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
