import base64
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("ios_testflight", ROOT / "ci/ios_testflight.py")
ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci)
NOW = dt.datetime(2026, 11, 21, tzinfo=dt.timezone.utc)
PROFILE_ID = "11111111-2222-3333-4444-555555555555"
CERT = b"synthetic-distribution-certificate"
FINGERPRINT = hashlib.sha1(CERT).hexdigest().upper()


def profile():
    return {
        "UUID": PROFILE_ID, "TeamIdentifier": [ci.TEAM],
        "ExpirationDate": (NOW + dt.timedelta(days=60)).replace(tzinfo=None),
        "DeveloperCertificates": [CERT],
        "Entitlements": {"application-identifier": f"{ci.TEAM}.{ci.BUNDLE}",
                         "get-task-allow": False, "beta-reports-active": True,
                         "aps-environment": "production"},
    }


def context():
    return {"GITHUB_ACTIONS": "true", "GITHUB_REPOSITORY": ci.REPOSITORY,
            "GITHUB_REF": "refs/heads/darx", "GITHUB_EVENT_NAME": "push", "RUNNER_OS": "macOS"}


class SafetyTests(unittest.TestCase):
    def test_only_canonical_darx_push_or_manual_is_allowed(self):
        for event in ["push", "workflow_dispatch"]:
            env = context()
            env["GITHUB_EVENT_NAME"] = event
            ci.require_context(env)
        for key, value in [("GITHUB_REF", "refs/heads/main"), ("GITHUB_REPOSITORY", "fork/FoundationChat"),
                           ("GITHUB_EVENT_NAME", "pull_request"), ("GITHUB_EVENT_NAME", "pull_request_target"),
                           ("GITHUB_ACTIONS", "false"), ("RUNNER_OS", "Linux")]:
            with self.subTest(key=key, value=value), self.assertRaises(ci.CIError):
                ci.require_context(dict(context(), **{key: value}))

    def test_integer_builds_preserve_app_update_contract_and_unique_attempts(self):
        self.assertEqual("101", ci.build_number("1", "1", "100"))
        self.assertEqual("102", ci.build_number("1", "2", "100"))
        self.assertEqual("109", ci.build_number("1", "9", "100"))
        self.assertEqual("111", ci.build_number("2", "1", "100"))
        for args in [(0, 1, 100), (1, 10, 100), (1, 1, 69), (9999, 1, 100), ("1;echo", 1, 100)]:
            with self.subTest(args=args), self.assertRaises(ci.CIError):
                ci.build_number(*args)

    def test_missing_secrets_are_named_without_values(self):
        with self.assertRaises(ci.CIError) as error:
            ci.require_secrets({"ASC_API_KEY_ID": "secret-sentinel"})
        self.assertIn("IOS_DISTRIBUTION_P12_BASE64", str(error.exception))
        self.assertNotIn("secret-sentinel", str(error.exception))

    def test_team_api_credentials_require_ids_not_an_individual_key(self):
        values = dict.fromkeys(ci.SECRET_NAMES, "synthetic")
        values.update(ASC_API_KEY_ID="ABCDEFGHIJ", ASC_API_ISSUER_ID=PROFILE_ID)
        ci.require_secrets(values)
        for key in ["ASC_API_KEY_ID", "ASC_API_ISSUER_ID"]:
            with self.subTest(key=key), self.assertRaises(ci.CIError):
                ci.require_secrets(dict(values, **{key: "private-sentinel"}))

    def test_base64_decoding_is_bounded_and_accepts_wrapped_input(self):
        self.assertEqual(b"example", ci.decode_secret(" ZXhh\nbXBsZQ== ", 7))
        for value, limit in [("", 10), ("%%%private-sentinel", 100), ("ZXhhbXBsZQ==", 6)]:
            with self.subTest(value=value), self.assertRaises(ci.CIError) as error:
                ci.decode_secret(value, limit)
            self.assertNotIn("private-sentinel", str(error.exception))

    def test_profile_requires_matching_team_bundle_and_production_push(self):
        self.assertEqual((PROFILE_ID, {FINGERPRINT}), ci.validate_profile(profile(), NOW))
        variants = []
        for key, value in [("TeamIdentifier", ["OTHERTEAM"]), ("ProvisionedDevices", []),
                           ("ProvisionsAllDevices", True), ("DeveloperCertificates", []),
                           ("UUID", "../../private"), ("ExpirationDate", NOW)]:
            item = profile()
            item[key] = value
            variants.append(item)
        for key, value in [("application-identifier", f"{ci.TEAM}.*"), ("get-task-allow", True),
                           ("aps-environment", "development"), ("beta-reports-active", False),
                           ("com.apple.developer.team-identifier", "OTHERTEAM")]:
            item = profile()
            item["Entitlements"][key] = value
            variants.append(item)
        for item in variants + [[], {"Entitlements": []}]:
            with self.subTest(item=str(type(item))), self.assertRaises(ci.CIError):
                ci.validate_profile(item, NOW)

    def test_export_is_internal_only_manual_and_does_not_rewrite_version(self):
        options = plistlib.loads(plistlib.dumps(ci.export_options(PROFILE_ID, FINGERPRINT)))
        self.assertIs(options["testFlightInternalTestingOnly"], True)
        self.assertEqual("upload", options["destination"])
        self.assertEqual("manual", options["signingStyle"])
        self.assertEqual({ci.BUNDLE: PROFILE_ID}, options["provisioningProfiles"])
        self.assertIs(options["manageAppVersionAndBuildNumber"], False)

    def test_failed_subprocess_never_exposes_password_arguments(self):
        with patch.object(ci.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "", "secret")):
            with self.assertRaises(ci.CIError) as error:
                ci.command(["security", "-P", "password-sentinel"], capture=True)
            self.assertNotIn("password-sentinel", str(error.exception))
            self.assertNotIn("secret", str(error.exception))

    def test_symlink_signing_directory_cannot_escape_runner_temp(self):
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as outside:
            Path(root, "mms-testflight-signing").symlink_to(outside, target_is_directory=True)
            with patch.dict(os.environ, {"RUNNER_TEMP": root}), self.assertRaises(ci.CIError):
                ci.signing_directory()

    def test_shared_scheme_contains_only_targets_that_exist(self):
        scheme = ET.parse(ROOT / "FoundationChat.xcodeproj/xcshareddata/xcschemes/FoundationChat.xcscheme")
        project = (ROOT / "FoundationChat.xcodeproj/project.pbxproj").read_text()
        for node in scheme.findall(".//BuildableReference"):
            self.assertIn(node.attrib["BlueprintIdentifier"], project)
        self.assertEqual([], scheme.findall(".//TestableReference"))


class ReleaseLifecycleTests(unittest.TestCase):
    def exercise(self, *, archive_failure=False, superseded=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / "home"
            home.mkdir()
            env = dict(context(), RUNNER_TEMP=str(root), GITHUB_SHA="a" * 40,
                       GITHUB_RUN_NUMBER="1", GITHUB_RUN_ATTEMPT="1", IOS_BUILD_NUMBER_BASE="100",
                       GITHUB_OUTPUT=str(root / "outputs"), GITHUB_STEP_SUMMARY=str(root / "summary"),
                       IOS_DISTRIBUTION_P12_PASSWORD="fixture-password", ASC_API_KEY_ID="ABCDEFGHIJ",
                       ASC_API_ISSUER_ID=PROFILE_ID)
            for name in ["IOS_DISTRIBUTION_P12_BASE64", "IOS_PROVISION_PROFILE_BASE64", "ASC_API_PRIVATE_KEY_BASE64"]:
                env[name] = base64.b64encode(b"synthetic-test-data").decode()
            calls = []
            heads = iter(["a" * 40, "b" * 40 if superseded else "a" * 40])

            def fake_command(args, capture=False):
                calls.append(args)
                if args[0] == "gh":
                    return next(heads)
                if args[:3] == ["security", "cms", "-D"]:
                    item = profile()
                    item["ExpirationDate"] = dt.datetime.now(dt.timezone.utc).replace(tzinfo=None) + dt.timedelta(days=60)
                    return plistlib.dumps(item).decode()
                if args[:2] == ["security", "list-keychains"]:
                    return '"/synthetic/login.keychain-db"' if "-s" not in args else ""
                if args[:2] == ["security", "create-keychain"]:
                    Path(args[-1]).touch()
                if args[:2] == ["security", "find-identity"]:
                    return FINGERPRINT
                if args[:2] == ["xcodebuild", "archive"] and archive_failure:
                    raise ci.CIError("Injected archive failure")
                return ""

            help_result = subprocess.CompletedProcess([], 0, "testFlightInternalTestingOnly", "")
            with patch.dict(os.environ, env), patch.object(Path, "home", return_value=home), \
                    patch.object(ci, "command", side_effect=fake_command), \
                    patch.object(ci.subprocess, "run", return_value=help_result), \
                    patch("builtins.print"):
                if archive_failure:
                    with self.assertRaisesRegex(ci.CIError, "Injected archive failure"):
                        ci.release()
                else:
                    ci.release()
                self.assertFalse(ci.signing_directory().exists())
                self.assertEqual([], list(home.rglob("*.mobileprovision")))
                ci.cleanup()  # safe when called again by the workflow's always step
            uploads = [args for args in calls if args[:2] == ["xcodebuild", "-exportArchive"]]
            self.assertEqual(0 if archive_failure or superseded else 1, len(uploads))
            if not archive_failure and not superseded:
                self.assertIn("uploaded=true", (root / "outputs").read_text())
            archive = next(args for args in calls if args[:2] == ["xcodebuild", "archive"])
            self.assertIn("CURRENT_PROJECT_VERSION=101", archive)

    def test_success_cleans_all_material_and_marks_upload(self):
        self.exercise()

    def test_archive_failure_cleans_material_and_never_uploads(self):
        self.exercise(archive_failure=True)

    def test_superseded_archive_is_not_uploaded(self):
        self.exercise(superseded=True)


if __name__ == "__main__":
    unittest.main()
