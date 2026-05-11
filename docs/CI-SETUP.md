# CI / TestFlight setup

> One-time setup to wire the GitHub Actions pipeline up to App Store Connect.
> After this, every merge to `master` automatically deploys to TestFlight,
> gated on lint + tests + build + code-review.

## Pipeline overview

```
PR opened → Claude code-review (posts comments)
PR / push → SwiftLint
            → Build (Ikeru / Watch / Widget)
            → Tests (IkeruCore + IkeruTests)
            → Device build sanity check
            → [only on push to master] Deploy to TestFlight
```

A red gate blocks the deploy. The artifact `Ikeru-<build>.xcarchive`
is uploaded to the workflow run for 14 days regardless of success.

## Required GitHub secrets

Open <https://github.com/NicolasBataille/Ikeru/settings/secrets/actions>
and add the following:

| Secret | What it is |
|---|---|
| `ASC_API_KEY_ID` | 10-char Key ID from App Store Connect |
| `ASC_ISSUER_ID` | UUID Issuer ID (top of the Keys page in ASC) |
| `ASC_API_KEY_BASE64` | The `.p8` file contents, base64-encoded |
| `IOS_DIST_CERT_P12_BASE64` | The Apple Distribution cert exported as `.p12`, base64-encoded |
| `IOS_DIST_CERT_P12_PASSWORD` | Password set when exporting the `.p12` |
| `APPLE_TEAM_ID` | 10-char team ID (currently `N84YXYF2NZ`) |
| `ANTHROPIC_API_KEY` | (Optional) For Claude code-review on PRs |

## Step 1 — Generate App Store Connect API Key

1. Go to <https://appstoreconnect.apple.com/access/api>
2. Click the **"+"** under *Keys* → name it `Ikeru CI` → role **App Manager**
3. Click **Generate**
4. **Download the `.p8` file immediately** (Apple only lets you download it once)
5. Note the **Key ID** and **Issuer ID** displayed on the page

Encode the `.p8` for GitHub:

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy
```

Paste into `ASC_API_KEY_BASE64`. Add `ASC_API_KEY_ID` and `ASC_ISSUER_ID` from the page.

## Step 2 — Export Distribution Certificate

If you've already shipped an app or built for TestFlight via Xcode, you
have a "Apple Distribution" cert in Keychain. Otherwise create one at
<https://developer.apple.com/account/resources/certificates/add>
(choose **iOS Distribution (App Store and Ad Hoc)**).

Then in Keychain Access:

1. Find **Apple Distribution: Nicolas Hugo Paul Bataille** under *My Certificates*
2. Right-click → **Export…** → format `.p12`
3. Set a strong password (you'll paste this as `IOS_DIST_CERT_P12_PASSWORD`)
4. Save somewhere local, then:

```bash
base64 -i ~/Desktop/IkeruDistCert.p12 | pbcopy
```

Paste into `IOS_DIST_CERT_P12_BASE64`.

## Step 3 — Register the app in App Store Connect

If `com.ikeru.app` doesn't exist yet in ASC:

1. Go to <https://appstoreconnect.apple.com/apps>
2. Click **"+"** → **New App**
3. Platform: **iOS**, Name: `Ikeru`, Bundle ID: `com.ikeru.app`,
   SKU: anything you want (`ikeru-001` works)
4. **Save**

Without this step, the upload to TestFlight will fail with "no app found
for bundle id".

## Step 4 — Add the GitHub Environment

The deploy job uses an environment called `testflight` for added safety
(can require manual approval, restrict by branch, etc.):

1. Go to <https://github.com/NicolasBataille/Ikeru/settings/environments>
2. Click **New environment** → name `testflight`
3. (Optional) Add **Required reviewers** → yourself, so each deploy waits
   for a manual click before running

## Step 5 — Anthropic API key (optional, for PR code review)

If you want the Claude code-review gate on PRs:

1. Go to <https://console.anthropic.com/settings/keys>
2. Create a new key → copy → add as `ANTHROPIC_API_KEY` secret
3. **Cost**: each PR review burns Claude tokens (~$0.10–0.50 per review
   depending on diff size). The workflow has `[skip-review]` PR-title
   escape hatch to skip the gate on hotfixes.

To disable the gate entirely, delete `.github/workflows/code-review.yml`
or remove the `ANTHROPIC_API_KEY` secret (the action will fail-soft).

## Step 6 — First deploy

Once secrets are in place, push to master (or merge a PR). Watch the run
at <https://github.com/NicolasBataille/Ikeru/actions>.

The first deploy may take 10–15 minutes (Apple processes the build before
it shows up in TestFlight). After Apple finishes processing, the build
appears in <https://appstoreconnect.apple.com/apps/<APP_ID>/testflight/ios>.

## Troubleshooting

**"No profile for team … and bundle identifier …"**
The `download-provisioning-profiles` action couldn't find an App Store
profile for `com.ikeru.app`. Either no provisioning profile exists yet,
or the API key doesn't have permission. Create one manually at
<https://developer.apple.com/account/resources/profiles/add> with type
**App Store** → bundle ID `com.ikeru.app` → cert from Step 2.

**"Invalid Authentication Token"**
The `.p8` was probably copied with extra whitespace or line breaks. Make
sure you used `base64 -i file.p8` (not `cat | base64`) so the encoding
is clean.

**"ITMS-90738: App Store Connect Operation Error"**
The build number didn't increment. The workflow uses a UTC-timestamp
build number (`YYYYMMDDHHMM`) which should be monotonic, but if two
deploys land in the same minute, the second fails. Re-run after a
minute.

**"No iTunes Connect API Key with this Key ID found"**
Your `.p8` file matches a different Key ID than `ASC_API_KEY_ID`.
Double-check that the secret matches the file you encoded.

**Build numbers / version bumping**
The workflow sets `CURRENT_PROJECT_VERSION` from the timestamp at
archive time — you don't need to bump `CFBundleVersion` manually in
the project file before each push.
