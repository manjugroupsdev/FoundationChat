"""MMS-260: guarded native signing/upload; never imports application code or calls MMS."""

import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import uuid

REPOSITORY = "manjugroupsdev/FoundationChat"
TEAM = "WLMZ5G3G5G"
BUNDLE = "com.manju.chat"
SECRET_NAMES = (
    "IOS_DISTRIBUTION_P12_BASE64", "IOS_DISTRIBUTION_P12_PASSWORD",
    "IOS_PROVISION_PROFILE_BASE64", "ASC_API_KEY_ID", "ASC_API_ISSUER_ID",
    "ASC_API_PRIVATE_KEY_BASE64",
)


class CIError(Exception):
    pass


def require_context(env):
    if (env.get("GITHUB_ACTIONS") != "true" or env.get("GITHUB_REPOSITORY") != REPOSITORY
            or env.get("GITHUB_REF") != "refs/heads/darx"
            or env.get("GITHUB_EVENT_NAME") not in {"push", "workflow_dispatch"}
            or env.get("RUNNER_OS") != "macOS"):
        raise CIError("Signing/upload is allowed only for this repository's darx on GitHub macOS.")


def build_number(run, attempt, base):
    values = [str(run), str(attempt), str(base)]
    if not all(re.fullmatch(r"[0-9]{1,4}", value) for value in values):
        raise CIError("Invalid CI build-number inputs.")
    run, attempt, base = map(int, values)
    if run < 1 or not 1 <= attempt <= 9 or base < 70:
        raise CIError("Require run >=1, attempt 1..9 and build base >=70.")
    number = base + (run - 1) * 10 + attempt
    if number > 9999:
        raise CIError("CI build range exhausted; review numbering before another upload.")
    return str(number)


def require_secrets(env):
    missing = [name for name in SECRET_NAMES if not env.get(name)]
    if missing:
        raise CIError("Missing GitHub Actions secrets: " + ", ".join(missing))
    if not re.fullmatch(r"[A-Z0-9]{10}", env["ASC_API_KEY_ID"]):
        raise CIError("ASC_API_KEY_ID must be the 10-character Apple key ID.")
    try:
        uuid.UUID(env["ASC_API_ISSUER_ID"])
    except (ValueError, AttributeError):
        raise CIError("ASC_API_ISSUER_ID must be the team API issuer UUID.") from None


def decode_secret(value, limit):
    try:
        data = base64.b64decode("".join(value.split()), validate=True)
    except (ValueError, TypeError):
        raise CIError("Invalid base64 signing secret; values are not logged.") from None
    if not data or len(data) > limit:
        raise CIError("Signing secret is empty or exceeds its size limit.")
    return data


def validate_profile(profile, now):
    if not isinstance(profile, dict) or not isinstance(profile.get("Entitlements"), dict):
        raise CIError("Invalid provisioning profile structure.")
    entitlements = profile.get("Entitlements", {})
    if (profile.get("TeamIdentifier") != [TEAM]
            or entitlements.get("application-identifier") != f"{TEAM}.{BUNDLE}"
            or entitlements.get("com.apple.developer.team-identifier", TEAM) != TEAM):
        raise CIError("Provisioning profile must match the MMS team and com.manju.chat exactly.")
    if (entitlements.get("get-task-allow") is not False
            or entitlements.get("beta-reports-active") is not True
            or entitlements.get("aps-environment") != "production"
            or "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices")):
        raise CIError("An App Store distribution profile with production push is required.")
    expires = profile.get("ExpirationDate")
    if not isinstance(expires, dt.datetime):
        raise CIError("Provisioning profile has no expiry date.")
    expires = expires.replace(tzinfo=dt.timezone.utc) if expires.tzinfo is None else expires
    if expires <= now + dt.timedelta(days=1):
        raise CIError("Provisioning profile expires within 24 hours; renew it before release.")
    try:
        profile_id = str(uuid.UUID(profile["UUID"])).upper()
    except (KeyError, ValueError, TypeError, AttributeError):
        raise CIError("Invalid provisioning profile UUID.") from None
    certificates = profile.get("DeveloperCertificates", [])
    if not certificates or not all(isinstance(cert, bytes) for cert in certificates):
        raise CIError("Provisioning profile contains no distribution certificate.")
    return profile_id, {hashlib.sha1(cert).hexdigest().upper() for cert in certificates}


def export_options(profile_id, certificate):
    return {
        "method": "app-store-connect", "destination": "upload", "teamID": TEAM,
        "signingStyle": "manual", "signingCertificate": certificate,
        "provisioningProfiles": {BUNDLE: profile_id},
        "manageAppVersionAndBuildNumber": False, "uploadSymbols": True,
        "testFlightInternalTestingOnly": True,
    }


def command(args, capture=False):
    result = subprocess.run(args, check=False, text=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    if result.returncode:
        # Do not include subprocess argv: security arguments contain passwords.
        raise CIError(f"{Path(args[0]).name} failed (exit {result.returncode}); credentials are not logged.")
    return result.stdout or ""


def signing_directory():
    root = Path(os.environ["RUNNER_TEMP"]).resolve()
    directory = (root / "mms-testflight-signing").resolve()
    if directory.parent != root:
        raise CIError("Signing directory is outside the runner temporary directory.")
    return directory


def write_private(path, data):
    with path.open("xb") as handle:
        os.chmod(path, 0o600)
        handle.write(data)


def latest_commit():
    return command(["gh", "api", f"repos/{REPOSITORY}/git/ref/heads/darx",
                    "--jq", ".object.sha"], capture=True).strip()


def release():
    require_context(os.environ)
    require_secrets(os.environ)
    number = build_number(os.environ["GITHUB_RUN_NUMBER"], os.environ["GITHUB_RUN_ATTEMPT"],
                          os.environ.get("IOS_BUILD_NUMBER_BASE", "100"))
    if latest_commit() != os.environ["GITHUB_SHA"]:
        print("Skipped: this commit is no longer the head of darx.")
        return
    help_result = subprocess.run(["xcodebuild", "-help"], capture_output=True, text=True, check=False)
    if "testFlightInternalTestingOnly" not in help_result.stdout + help_result.stderr:
        raise CIError("Selected Xcode cannot confirm internal-only export support; upload refused.")
    directory = signing_directory()
    directory.mkdir(mode=0o700)
    state = {"profiles": [], "keychains": [], "keychain": str(directory / "signing.keychain-db")}
    state_file = directory / "cleanup.json"

    def save_state():
        state_file.write_text(json.dumps(state), encoding="utf-8")

    save_state()
    try:
        p12, profile, key = directory / "distribution.p12", directory / "profile.mobileprovision", directory / "AuthKey.p8"
        write_private(p12, decode_secret(os.environ["IOS_DISTRIBUTION_P12_BASE64"], 5_000_000))
        write_private(profile, decode_secret(os.environ["IOS_PROVISION_PROFILE_BASE64"], 2_000_000))
        write_private(key, decode_secret(os.environ["ASC_API_PRIVATE_KEY_BASE64"], 64_000))
        command(["openssl", "pkey", "-in", str(key), "-noout"], capture=True)
        decoded = command(["security", "cms", "-D", "-i", str(profile)], capture=True)
        profile_id, certificates = validate_profile(plistlib.loads(decoded.encode()), dt.datetime.now(dt.timezone.utc))
        password = secrets.token_urlsafe(32)
        print(f"::add-mask::{password}", flush=True)
        state["keychains"] = shlex.split(command(["security", "list-keychains", "-d", "user"], capture=True))
        save_state()
        keychain = state["keychain"]
        command(["security", "create-keychain", "-p", password, keychain], capture=True)
        command(["security", "set-keychain-settings", "-lut", "3600", keychain], capture=True)
        command(["security", "unlock-keychain", "-p", password, keychain], capture=True)
        command(["security", "import", str(p12), "-k", keychain, "-P", os.environ["IOS_DISTRIBUTION_P12_PASSWORD"],
                 "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"], capture=True)
        command(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password, keychain], capture=True)
        command(["security", "list-keychains", "-d", "user", "-s", keychain, *state["keychains"]], capture=True)
        identities = command(["security", "find-identity", "-v", "-p", "codesigning", keychain], capture=True)
        matches = certificates.intersection(re.findall(r"\b[A-F0-9]{40}\b", identities))
        if len(matches) != 1:
            raise CIError("P12 must contain one valid signing identity matching the provisioning profile.")
        certificate = next(iter(matches))
        for folder in [Path.home() / "Library/MobileDevice/Provisioning Profiles",
                       Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"]:
            folder.mkdir(parents=True, exist_ok=True)
            installed = folder / f"{profile_id}.mobileprovision"
            if installed.exists():
                raise CIError("Refusing to overwrite an existing provisioning profile on the runner.")
            state["profiles"].append(str(installed))
            save_state()
            write_private(installed, profile.read_bytes())
        options = directory / "InternalExportOptions.plist"
        write_private(options, plistlib.dumps(export_options(profile_id, certificate)))
        archive = Path(os.environ["RUNNER_TEMP"]) / "mms-internal.xcarchive"
        command(["xcodebuild", "archive", "-project", "FoundationChat.xcodeproj", "-scheme", "FoundationChat",
                 "-configuration", "Release", "-destination", "generic/platform=iOS", "-archivePath", str(archive),
                 "-derivedDataPath", str(Path(os.environ["RUNNER_TEMP"]) / "release-derived"),
                 "-onlyUsePackageVersionsFromResolvedFile", f"CURRENT_PROJECT_VERSION={number}",
                 f"DEVELOPMENT_TEAM={TEAM}", "CODE_SIGN_STYLE=Manual", f"CODE_SIGN_IDENTITY={certificate}",
                 f"PROVISIONING_PROFILE_SPECIFIER={profile_id}", "APS_ENVIRONMENT=production"])
        if latest_commit() != os.environ["GITHUB_SHA"]:
            print("Archive complete, upload skipped: darx now contains a newer commit.")
            return
        command(["xcodebuild", "-exportArchive", "-archivePath", str(archive),
                 "-exportPath", str(Path(os.environ["RUNNER_TEMP"]) / "mms-internal-export"),
                 "-exportOptionsPlist", str(options), "-authenticationKeyPath", str(key),
                 "-authenticationKeyID", os.environ["ASC_API_KEY_ID"],
                 "-authenticationKeyIssuerID", os.environ["ASC_API_ISSUER_ID"],
                 "-allowProvisioningUpdates"])
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write("uploaded=true\n")
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
            summary.write(f"Uploaded internal-only M-Chat build {number}, commit `{os.environ['GITHUB_SHA']}`.\n"
                          "Apple processing and existing internal automatic-distribution groups control availability.\n")
    finally:
        cleanup()


def cleanup():
    directory = signing_directory()
    state_file = directory / "cleanup.json"
    if not state_file.exists():
        return
    state = json.loads(state_file.read_text(encoding="utf-8"))
    if state.get("keychains"):
        subprocess.run(["security", "list-keychains", "-d", "user", "-s", *state["keychains"]],
                       capture_output=True, check=False)
    keychain = directory / "signing.keychain-db"
    if keychain.exists():
        subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True, check=False)
    allowed = {Path.home() / "Library/MobileDevice/Provisioning Profiles",
               Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"}
    for value in state.get("profiles", []):
        path = Path(value)
        if path.parent in allowed and re.fullmatch(r"[A-F0-9-]{36}\.mobileprovision", path.name):
            path.unlink(missing_ok=True)
    shutil.rmtree(directory)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2 or sys.argv[1] not in {"release", "cleanup"}:
            raise CIError("Use release or cleanup.")
        {"release": release, "cleanup": cleanup}[sys.argv[1]]()
    except (CIError, OSError, ValueError, KeyError) as error:
        # Generic parser/OS exceptions can include input; only intentional errors are safe.
        message = str(error) if isinstance(error, CIError) else "CI signing operation failed; secret values are not logged."
        print(f"::error::{message}", file=sys.stderr)
        sys.exit(1)
