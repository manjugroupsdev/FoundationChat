# MMS-260: Internal TestFlight Delivery

Repository: `manjugroupsdev/FoundationChat`. App: M-Chat / `com.manju.chat`.
Team: `WLMZ5G3G5G`. App Store Connect app: `6760779940`.

Pushes to `darx` run `.github/workflows/ios-internal-testflight.yml`:

1. GitHub-hosted Apple Silicon macOS 26, Xcode 26.3.
2. CI safety tests, the existing 15 Swift helper harnesses, locked package
   resolution, and a native Release simulator build without signing.
3. A separate, dependent job validates credentials, archives with an existing
   distribution identity, and uploads with the internal-only export flag.
4. Signing material is removed even on failure. Only build diagnostics and
   dSYMs are retained, never P12/P8/profile files, keychains or credential state.

There is no public App Store submission, external-testing submission, schedule,
PR trigger, MMS API call, mobile runtime change or production deployment.
Manual runs also refuse any branch other than `darx` or another repository.
Uploads are serialized and check the current `darx` SHA before signing and
again before upload. A newer push does not kill an upload already in progress.

## Required GitHub Actions Secrets

Add these directly at:
`https://github.com/manjugroupsdev/FoundationChat/settings/secrets/actions`.
Do not paste their values into chat, a Cheetos task, a commit or an issue.

| Secret | What Manoj / the signing administrator must supply |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | Base64 of an **Apple Distribution** certificate exported **with its private key** as a password-protected `.p12`. A `.cer` alone cannot sign. |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Password used when exporting that P12. |
| `IOS_PROVISION_PROFILE_BASE64` | Base64 of the matching **App Store** `.mobileprovision` for `com.manju.chat`, team `WLMZ5G3G5G`, production push entitlement, valid for more than 24 hours. Not Development, Ad Hoc or Enterprise. Must contain the P12 certificate. |
| `ASC_API_KEY_ID` | The 10-character ID of a dedicated **team** App Store Connect API key. Developer upload permissions suffice with existing manual signing assets; broader permissions are not required by this workflow. |
| `ASC_API_ISSUER_ID` | Issuer UUID shown with that team API key. An individual key without an issuer is not this setup. |
| `ASC_API_PRIVATE_KEY_BASE64` | Base64 of that key's downloaded `AuthKey_….p8` private-key file. |

Use existing valid signing assets when possible. Cloud-managed signing keys
are not exportable: if there is no matching exportable distribution private
key, an authorized signing administrator must supply/create the identity first.
Do not revoke an existing distribution certificate or change push permissions
to make this workflow run. No Apple ID password, OTP, PostHog key, Android key,
MMS session token or backend credential is needed.

On Manoj's Mac, convert each file to a single-line base64 value, for example:

```bash
base64 -i Distribution.p12 | tr -d '\n' | pbcopy
```

Paste into the corresponding **GitHub secret**, then repeat for the profile
and P8 file. Signing credentials will be sent only to the private GitHub
runner and Apple's signing/upload tools. Certificate/private-key access and
API-key creation need the operator's approval; this change creates neither.
The temporary runner keychain password is generated per job, not another
repository secret. GitHub-hosted macOS runs consume the account's Actions quota.

## Build Numbers And Distribution

CI overrides the build number for the archive only; source stays unchanged.
The integer formula is `base + (run_number - 1) * 10 + run_attempt`, with base
100 by default. The first upload is 101, a retry is 102, and the next run is
111. Attempts are restricted to 1..9 and builds to 9999. This preserves the
existing app updater's integer-build contract and stays above uploaded build70.
If another release process uploads a higher build, set repository variable
`IOS_BUILD_NUMBER_BASE` to a suitable higher integer before using this workflow.
Do not rename/reset the workflow's run-number history without reviewing this.

The Xcode export explicitly sets `testFlightInternalTestingOnly=true`.
Existing App Store Connect **automatic internal groups** determine recipients;
the current `mms team` group already uses Automatic for Xcode Builds. This
workflow does not add testers or alter any group's automatic-distribution
setting. Apple processing can delay availability after the upload completes;
an upload success is not proof of processing success or installation.

## Validation And First Activation

```bash
python3 -m unittest discover -s ci/tests -v
bash tests/run-mobile-helper-tests.sh
```

The shared scheme previously referenced `FoundationChatTests`, but the project
has no such target and ignores that unfinished folder. Only those dangling
scheme references were removed. CI runs actual standalone helper tests and a
native simulator build; it does **not** claim an `xcodebuild test` XCTest suite.

Missing secrets fail the release job with secret **names**, never their values.
The validation job still runs without signing credentials. The first real
signed archive/upload remains pending until all six secrets are configured.
After setup, rerun the failed release job on the latest `darx` run or push a
new commit to `darx`. The repository's default branch is `main`: GitHub only
offers manual workflow dispatch when the workflow also exists on that default
branch. This change does not touch `main` or change the default branch; automatic
`darx` pushes work independently of the manual-dispatch button.
Verify the commit/build in Actions, then Apple's processing status and the new
internal TestFlight build before claiming delivery or iPhone validation.

Native signing, simulator compilation, package/plugin behavior and upload
cannot be established by a Windows/WSL SDK shim or mocked unit tests alone.
If Apple rejects signing/upload, use the Actions log; do not add MMS probes,
automatic upload retry loops or loosen signature/entitlement validation.
