#!/bin/bash
# Makes the build of Sill for iPhone and iPad that goes to App Store Connect (TestFlight, then the
# App Store): a Release archive of iOSClient/Sill.xcodeproj, signed for App Store Connect and
# exported as an .ipa on this Mac, or uploaded.
#
#   Scripts/release-ios.sh                    archive, export .build/ios/export/Sill.ipa and check it;
#                                             nothing goes to App Store Connect
#   Scripts/release-ios.sh --upload           the same, then the archive goes to App Store Connect,
#                                             where it becomes a TestFlight build
#   Scripts/release-ios.sh --bump --upload    first the next build number, committed alone: every
#                                             upload of a version after its first
#   Scripts/release-ios.sh --upload --api-key ~/keys/AuthKey_ABC123DEFG.p8 --api-issuer <issuer ID>
#                                             signs and uploads through an App Store Connect API key
#                                             instead of the Apple Account signed in to Xcode
#   Scripts/release-ios.sh --sign-at-export   archives without signing and lets the export sign: for
#                                             a Mac or runner with no development certificate (the
#                                             TestFlight workflow, with --api-key)
#   Scripts/release-ios.sh --unsigned         archive without signing, zip the app and check it: no
#                                             Apple Account, no certificate, nothing to install or
#                                             upload (the TestFlight workflow without its key)
#   Scripts/release-ios.sh --print-version    the version and build the next archive gets: 0.5 (1)
#   Scripts/release-ios.sh --privacy-report [archive]
#                                             what an archive's privacy manifests declare and which
#                                             required-reason APIs its binary uses; how to make
#                                             Xcode's privacy report
#
# Signing is Xcode's automatic signing on team 9B2KKVM937, as the project sets it. The archive is
# signed for development (Apple Development), as Product › Archive signs it; the export signs it
# again for App Store Connect with an Apple Distribution certificate and an App Store provisioning
# profile. -allowProvisioningUpdates lets xcodebuild make or renew those through the Apple Account
# in Xcode › Settings › Accounts, or through the API key. The first export (2026-09-26, this
# script's rehearsal) made a cloud-managed Apple Distribution certificate, whose private key stays
# with Apple (nothing went into the keychain), and the profile "iOS Team Store Provisioning
# Profile: me.saffer.sill"; later exports reuse both, and Xcode renews them. An archive made
# without signing exports the same way, with the same entitlements: --sign-at-export.
#
# Uploading needs the app's record in App Store Connect (docs/release-checklist.md, TestFlight) and
# a build number that version hasn't had: --bump. Uploading takes the Account Holder, Admin or App
# Manager role; signing through an API key (cloud-managed certificates) takes Admin.
#
# Nothing here stores a credential. The API key file stays where you keep it (outside the
# repository: the script refuses a key inside it) and only its path goes to xcodebuild; with the
# Apple Account, Xcode holds the sign-in, as it does for Product › Archive.
#
# Why each step:
# - Xcode 27 or nothing: App Store Connect takes builds made with a current SDK only, and the
#   project, CI and Sill for Mac are all built with Xcode 27. Raise `xcode_major` with them.
# - --bump refuses a working tree with changes because it commits the new number alone: an
#   uploaded build then names exactly one commit. The export keeps the project's number
#   (manageAppVersionAndBuildNumber NO in Packaging/ExportOptions-appstore.plist), so App Store
#   Connect refuses a number it has seen instead of Xcode quietly picking another.
# - The archive and every xcodebuild step log to .build/ios/*.log; this prints one line per step
#   and, when one fails, its errors and what usually fixes them.
# - The exported .ipa is unpacked and checked before anything is uploaded: the version and build
#   the project says, the export compliance key (ITSAppUsesNonExemptEncryption NO, so no build
#   waits on Missing Compliance), the Local Network and camera strings, the privacy manifest, an
#   Apple Distribution signature, an App Store profile (no device list) and no get-task-allow.
# - The required-reason check reads the binary the way App Store Connect's upload check does
#   (ITMS-91053): C functions and constants it imports, Objective-C selectors it calls. It knows
#   Apple's list of those APIs, not every way to reach them, so it warns rather than refuses.
# - --upload exports a second time with destination "upload": xcodebuild uploads only from an
#   archive, so the .ipa checked above is its twin, made the same way from the same archive.
# - xcodebuild has no command for Xcode's privacy report (Xcode 27.0's xcodebuild -help has none;
#   the Organizer makes it), so --privacy-report prints what that report is made of and the way
#   to it.
set -euo pipefail

usage() {
    cat <<'USAGE'
usage: Scripts/release-ios.sh [--bump] [--upload] [--sign-at-export] [--api-key PATH --api-issuer ID [--api-key-id ID]] [-v]
       Scripts/release-ios.sh --unsigned
       Scripts/release-ios.sh --print-version
       Scripts/release-ios.sh --privacy-report [ARCHIVE]

  (no option)
      archives Sill for iPhone and iPad (Release, generic/platform=iOS) into .build/ios/Sill.xcarchive,
      exports it for App Store Connect into .build/ios/export/Sill.ipa and checks the .ipa.
      Nothing goes to App Store Connect.
  --upload
      then uploads the archive to App Store Connect, where it becomes a TestFlight build. It needs
      the app's record there (bundle ID me.saffer.sill) and a build number not uploaded before.
  --bump
      first adds 1 to CURRENT_PROJECT_VERSION in iOSClient/Sill.xcodeproj and commits that alone
      ("iOS: build N of version V"). Refuses when the working tree has changes.
  --api-key PATH --api-issuer ID [--api-key-id ID]
      an App Store Connect API key (App Store Connect › Users and Access › Integrations › App Store
      Connect API) for signing and uploading, instead of the Apple Account in Xcode › Settings ›
      Accounts. PATH is the AuthKey_<Key ID>.p8 file, kept outside the repository; the Key ID
      comes from its name unless --api-key-id gives it. Signing through a key (cloud-managed
      certificates) needs the Admin role; uploading, Admin or App Manager.
  --sign-at-export
      archives without signing; the export signs (Apple Distribution, App Store profile) as it
      always does. For a Mac or runner without a development certificate, such as the TestFlight
      workflow's.
  --unsigned
      archives without signing and zips the app as .build/ios/export/Sill-unsigned.ipa, then
      checks it: no Apple Account or certificate needed, and the result can be neither installed
      nor uploaded. For CI without the API key.
  --print-version
      prints the version and build the next archive gets, such as 0.5 (1), and exits.
  --privacy-report [ARCHIVE]
      prints what the privacy manifests in ARCHIVE (default .build/ios/Sill.xcarchive) declare and
      which required-reason APIs its binary uses, and how to make Xcode's privacy report (a PDF,
      made only by the Organizer).
  -v, --verbose
      also shows xcodebuild's own output (it always goes to .build/ios/*.log).

Every mode that builds refuses to start unless Xcode 27 is selected.
docs/release-checklist.md, "TestFlight", has the App Store Connect side.
USAGE
}

project=iOSClient/Sill.xcodeproj
pbxproj="$project/project.pbxproj"
scheme=Sill
bundle_id=me.saffer.sill
team=9B2KKVM937
xcode_major=27
export_options=Packaging/ExportOptions-appstore.plist
links=iOSClient/SillLinks.swift
out=.build/ios
archive="$out/Sill.xcarchive"
export_dir="$out/export"

verbose=0
auth=()          # xcodebuild's -authenticationKey* arguments, when an API key is given
signer="the Apple Account in Xcode"   # who Xcode signs and uploads through, for the step lines
unpacked=""      # an .ipa's copy being checked; removed on exit

say() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
cleanup() { if [ -n "$unpacked" ]; then rm -rf "$unpacked"; fi; }

# One value of a plist file, or a failure (PlistBuddy prints its complaints on stdout, so its output
# counts only when it succeeds). Keys may hold dots: PlistBuddy's separator is the colon.
plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2" 2>/dev/null
}

# The selected Xcode as "<version> <build>", such as "27.0 27A266a", or nothing.
xcode_version() {
    xcodebuild -version 2>/dev/null \
        | awk '$1 == "Xcode" { v = $2 } $1 == "Build" && $2 == "version" { b = $3 } END { if (v != "") printf "%s %s\n", v, b }' \
        || true
}

# Why the selected Xcode can't make this build, or nothing.
xcode_problem() {
    local info version dir
    info="$(xcode_version)"
    version="${info%% *}"
    dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || echo nothing)}"
    if [ -z "$info" ]; then
        echo "xcodebuild doesn't answer (the developer directory is $dir). Select Xcode $xcode_major: sudo xcode-select -s /Applications/Xcode.app"
    elif [ "${version%%.*}" != "$xcode_major" ]; then
        echo "The selected Xcode is $version ($dir), and Sill for iPhone and iPad is built for App Store Connect with Xcode $xcode_major. Select it with sudo xcode-select -s /Applications/Xcode.app, or for one run: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/release-ios.sh"
    fi
}

# Every value the project gives the build setting $1, one per line, without quotes: the Sill
# target's Debug and Release configurations set MARKETING_VERSION and CURRENT_PROJECT_VERSION.
setting_values() {
    sed -n -E "s/^[[:space:]]*$1 = \"?([^\";]*)\"?;[[:space:]]*\$/\1/p" "$pbxproj" | sort -u
}

# The one value of the build setting $1, or a message and a failure when there is none or the
# configurations disagree.
project_setting() {
    local key="$1" values
    values="$(setting_values "$key")"
    if [ -z "$values" ]; then
        echo "$pbxproj sets no $key." >&2
        return 1
    fi
    if [ "$(printf '%s\n' "$values" | wc -l | tr -d ' ')" != 1 ]; then
        echo "$pbxproj sets $key to $(printf '%s\n' "$values" | paste -s -d ',' - | sed 's/,/ and /g') in different configurations; give Debug and Release of the target Sill the same value (General › Identity)." >&2
        return 1
    fi
    printf '%s\n' "$values"
}

# --bump: CURRENT_PROJECT_VERSION + 1 in every configuration, committed alone. Refuses a working
# tree with changes to tracked files (untracked ones can't be in the build: the project lists its
# files).
bump_build() {
    local version="$1" build="$2" next dirty others
    dirty="$(git status --porcelain --untracked-files=no)"
    if [ -n "$dirty" ]; then
        {
            echo "error: --bump commits the new build number alone, and the working tree has changes:"
            printf '%s\n' "$dirty" | sed 's/^/  /'
            echo "Commit or stash them first. Nothing was changed."
        } >&2
        exit 2
    fi
    if ! [[ "$build" =~ ^[0-9]+$ ]]; then
        fail "--bump adds 1 to a whole number, and CURRENT_PROJECT_VERSION is '$build'. Set the next number in Xcode (target Sill › General › Build) and commit it. Nothing was changed."
    fi
    next=$((10#$build + 1))
    sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION = )\"?$build\"?;[[:space:]]*\$/\1$next;/" "$pbxproj"
    others="$(git status --porcelain --untracked-files=no | grep -v -F " $pbxproj" || true)"
    if [ "$(setting_values CURRENT_PROJECT_VERSION)" != "$next" ] || [ -n "$others" ]; then
        git checkout -- "$pbxproj"
        fail "the build number didn't change to $next everywhere in $pbxproj; it is back as it was."
    fi
    git commit -q -m "iOS: build $next of version $version" \
        -m "The next build for App Store Connect (Scripts/release-ios.sh --bump)." -- "$pbxproj"
    say "Build number $build → $next, committed as $(git rev-parse --short HEAD) (iOS: build $next of version $version)"
}

# --api-key and its companions into xcodebuild's -authenticationKey* arguments. Refuses a key
# inside the repository: a key there is one `git add -A` away from a commit.
use_api_key() {
    local key="$1" issuer="$2" key_id="$3" dir file root
    if [ -z "$issuer" ]; then fail "--api-key needs --api-issuer: the Issuer ID above the keys in App Store Connect › Users and Access › Integrations › App Store Connect API."; fi
    if [ ! -f "$key" ] || [ ! -r "$key" ]; then fail "--api-key: $key is not a file this user can read."; fi
    dir="$(cd "$(dirname "$key")" && pwd -P)"
    file="$(basename "$key")"
    root="$(pwd -P)"
    case "$dir/" in
        "$root/"*) fail "--api-key: $key is inside the repository. Keep it outside (not in Downloads either), where docs/release-checklist.md keeps the notary key; nothing here copies it." ;;
    esac
    if [ -z "$key_id" ]; then
        key_id="$(printf '%s' "$file" | sed -n -E 's/^AuthKey_([A-Za-z0-9]+)\.p8$/\1/p')"
        if [ -z "$key_id" ]; then fail "--api-key: $file isn't named AuthKey_<Key ID>.p8, as App Store Connect names it; give the Key ID with --api-key-id."; fi
    fi
    if ! [[ "$key_id" =~ ^[A-Za-z0-9]{8,16}$ ]]; then fail "--api-key-id: '$key_id' doesn't look like a Key ID (ten letters and digits, such as ABC123DEFG)."; fi
    if ! [[ "$issuer" =~ ^[0-9A-Fa-f-]{36}$ ]]; then fail "--api-issuer: '$issuer' doesn't look like an Issuer ID (a UUID, such as 69a6de70-…)."; fi
    auth=(-authenticationKeyPath "$dir/$file" -authenticationKeyID "$key_id" -authenticationKeyIssuerID "$issuer")
    signer="the App Store Connect API key $key_id"
}

# Runs a command with its output in the log $1 (and on the terminal too with --verbose).
run_logged() {
    local log="$1"
    shift
    if [ "$verbose" = 1 ]; then
        "$@" 2>&1 | tee "$log"
    else
        "$@" >"$log" 2>&1
    fi
}

# The errors in an xcodebuild log, and what usually fixes the ones seen before, on stderr.
explain_failure() {
    local log="$1" what="$2" lines
    lines="$(grep -E '(^|[[:space:]])(error|fatal error):|\*\* [A-Z ]+ FAILED \*\*' "$log" \
        | grep -v 'failed with exit code 0' | sed -E 's/^[[:space:]]+//' | awk '!seen[$0]++' | head -20 || true)"
    {
        echo "error: $what failed. Its errors, from $log:"
        if [ -n "$lines" ]; then printf '%s\n' "$lines" | sed 's/^/  /'; else tail -n 15 "$log" | sed 's/^/  /'; fi
        if grep -q -i -E 'No Accounts|No account for team|Sign in with your Apple ID|requires a development team|No signing certificate|No profiles for|No provisioning profile' "$log"; then
            echo "Xcode has no way to sign for team $team here: add its Apple Account in Xcode › Settings › Accounts (it makes and renews the certificates and profiles), or give --api-key and --api-issuer."
        fi
        if grep -q -i 'Cloud signing permission error' "$log"; then
            echo "The API key may not use cloud-managed distribution certificates: signing through a key needs one with the Admin role (App Store Connect › Users and Access › Integrations)."
        fi
        if grep -q -i -E 'App Store Connect access|not a member of|Unable to authenticate' "$log"; then
            echo "The account or key can't reach App Store Connect for team $team: check the Apple Account in Xcode › Settings › Accounts (signed in, a role that may upload), or the API key and its role."
        fi
        if grep -q -i 'No suitable application records' "$log"; then
            echo "App Store Connect has no app with the bundle ID $bundle_id yet: create its record (docs/release-checklist.md, TestFlight, step 1), then run this again."
        fi
        if grep -q -i -E 'Redundant Binary Upload|must be higher than the previously uploaded|already uploaded a build' "$log"; then
            echo "App Store Connect already has this build number for this version: run again with --bump."
        fi
    } >&2
}

# The export compliance key, the Local Network and camera strings, the privacy manifest, the bundle
# ID, version and build, in the app bundle $1: fails on anything App Store Connect or TestFlight
# would hold against it, and prints a summary line unless $4 is 1.
check_app() {
    local app="$1" version="$2" build="$3" quiet="${4:-0}" plist="$1/Info.plist" value
    value="$(plist_value CFBundleIdentifier "$plist")" || value=""
    [ "$value" = "$bundle_id" ] || fail "$app has the bundle ID '$value', not $bundle_id."
    value="$(plist_value CFBundleShortVersionString "$plist")" || value=""
    [ "$value" = "$version" ] || fail "$app is version '$value', but the project says $version."
    value="$(plist_value CFBundleVersion "$plist")" || value=""
    [ "$value" = "$build" ] || fail "$app is build '$value', but the project says $build."
    value="$(plist_value ITSAppUsesNonExemptEncryption "$plist")" || value="missing"
    [ "$value" = false ] || fail "$app's ITSAppUsesNonExemptEncryption is $value, not NO: every build would wait on Missing Compliance (iOSClient/Info.plist; docs/app-store-metadata.md §6)."
    plist_value NSLocalNetworkUsageDescription "$plist" >/dev/null || fail "$app has no NSLocalNetworkUsageDescription: iOS would never ask for Local Network access."
    value="$(plist_value NSBonjourServices "$plist")" || value=""
    grep -F '_sill._tcp' >/dev/null <<<"$value" || fail "$app's NSBonjourServices lacks _sill._tcp: the device would find no Mac."
    plist_value NSCameraUsageDescription "$plist" >/dev/null || fail "$app has no NSCameraUsageDescription: Add a Mac…'s scanner would crash it."
    [ -f "$app/PrivacyInfo.xcprivacy" ] || fail "$app has no PrivacyInfo.xcprivacy: App Store Connect refuses an upload whose required-reason APIs aren't declared (ITMS-91053)."
    plutil -lint -s "$app/PrivacyInfo.xcprivacy" || fail "$app/PrivacyInfo.xcprivacy is not a valid property list."
    if [ "$quiet" = 0 ]; then
        say "Checked its Sill.app: $version ($build), $bundle_id, ITSAppUsesNonExemptEncryption NO, the Local Network, Bonjour (_sill._tcp) and camera entries, PrivacyInfo.xcprivacy"
    fi
}

# Apple's required-reason APIs as a binary shows them, "<category> <symbol|selector> <name>":
# C functions and constants the binary imports, Objective-C selectors it calls. From Apple's
# "Describing use of required reason API"; a Swift property such as ProcessInfo.systemUptime or
# UserDefaults.standard reaches the binary as its selector or class. getattrlist and its kin are on
# both the file timestamp and the disk space lists: either declaration covers them.
required_reason_apis() {
    cat <<'LIST'
FileTimestamp symbol stat
FileTimestamp symbol fstat
FileTimestamp symbol fstatat
FileTimestamp symbol lstat
FileTimestamp symbol getattrlistbulk
FileTimestamp symbol NSFileCreationDate
FileTimestamp symbol NSFileModificationDate
FileTimestamp symbol NSURLCreationDateKey
FileTimestamp symbol NSURLContentModificationDateKey
FileTimestamp selector fileCreationDate
FileTimestamp selector fileModificationDate
FileTimestamp|DiskSpace symbol getattrlist
FileTimestamp|DiskSpace symbol fgetattrlist
FileTimestamp|DiskSpace symbol getattrlistat
SystemBootTime symbol mach_absolute_time
SystemBootTime selector systemUptime
DiskSpace symbol statfs
DiskSpace symbol statvfs
DiskSpace symbol fstatfs
DiskSpace symbol fstatvfs
DiskSpace symbol NSFileSystemFreeSize
DiskSpace symbol NSFileSystemSize
DiskSpace symbol NSURLVolumeAvailableCapacityKey
DiskSpace symbol NSURLVolumeAvailableCapacityForImportantUsageKey
DiskSpace symbol NSURLVolumeAvailableCapacityForOpportunisticUsageKey
DiskSpace symbol NSURLVolumeTotalCapacityKey
ActiveKeyboards selector activeInputModes
UserDefaults symbol OBJC_CLASS_$_NSUserDefaults
UserDefaults selector standardUserDefaults
LIST
}

# The required-reason API categories the privacy manifests in $1 (a folder) declare, one per line,
# such as UserDefaults.
declared_categories() {
    local manifest i type
    find "$1" -name PrivacyInfo.xcprivacy -type f 2>/dev/null | while IFS= read -r manifest; do
        i=0
        while type="$(plutil -extract "NSPrivacyAccessedAPITypes.$i.NSPrivacyAccessedAPIType" raw -o - "$manifest" 2>/dev/null)"; do
            printf '%s\n' "${type#NSPrivacyAccessedAPICategory}"
            i=$((i + 1))
        done
    done | sort -u
}

# Which required-reason APIs the app's binary uses, against what its manifests declare: one line,
# and a warning naming each API that no manifest declares.
check_required_reasons() {
    local app="$1" bin symbols selectors declared categories kind name shown used="" missing="" alternative covered
    bin="$app/$(plist_value CFBundleExecutable "$app/Info.plist" || echo Sill)"
    symbols="$(nm -u "$bin" 2>/dev/null | sed 's/^_//' || true)"
    selectors="$(otool -v -s __TEXT __objc_methname "$bin" 2>/dev/null | tr -s ' \t' '\n\n' || true)"
    declared="$(declared_categories "$app")"
    while read -r categories kind name; do
        # Here-strings, not pipes: under pipefail, grep -q leaving early could fail the pipe.
        if [ "$kind" = symbol ]; then
            grep -x -F -e "$name" >/dev/null <<<"$symbols" || continue
        else
            grep -x -F -e "$name" >/dev/null <<<"$selectors" || continue
        fi
        shown="${name#OBJC_CLASS_\$_}"
        used="$used${categories//|/ or }"$'\t'"$shown"$'\n'
        covered=0
        for alternative in ${categories//|/ }; do
            if grep -x -F -e "$alternative" >/dev/null <<<"$declared"; then covered=1; fi
        done
        if [ "$covered" = 0 ]; then missing="$missing ${categories//|/ or } ($shown)"; fi
    done < <(required_reason_apis)
    if [ -z "$used" ]; then
        say "Required-reason APIs: the binary uses none of Apple's list"
    else
        say "Required-reason APIs in the binary: $(printf '%s' "$used" | awk -F '\t' 'NF == 2 { if (!($1 in n)) order[++k] = $1; n[$1] = n[$1] (n[$1] == "" ? "" : ", ") $2 } END { for (i = 1; i <= k; i++) printf "%s%s (%s)", (i > 1 ? "; " : ""), order[i], n[order[i]] }'); declared: $(printf '%s\n' "$declared" | paste -s -d ',' - | sed -e 's/,/, /g' -e 's/^$/none/')"
    fi
    if [ -n "$missing" ]; then
        warn "the binary uses required-reason APIs that no privacy manifest declares:$missing. App Store Connect refuses such an upload (ITMS-91053): add each category and its reason to iOSClient/PrivacyInfo.xcprivacy (docs/app-store-metadata.md §4 and the Layout note in CLAUDE.md)."
    fi
}

# One privacy manifest in words.
describe_manifest() {
    local manifest="$1" base="$2" tracking domains collected i type reasons j reason list=""
    tracking="$(plutil -extract NSPrivacyTracking raw -o - "$manifest" 2>/dev/null || echo 'not set')"
    domains="$(plutil -extract NSPrivacyTrackingDomains raw -o - "$manifest" 2>/dev/null || echo 0)"
    collected="$(plutil -extract NSPrivacyCollectedDataTypes raw -o - "$manifest" 2>/dev/null || echo 0)"
    echo "  ${manifest#"$base"/}"
    echo "    tracking: $tracking; tracking domains: $domains; collected data types: $collected"
    i=0
    while type="$(plutil -extract "NSPrivacyCollectedDataTypes.$i.NSPrivacyCollectedDataType" raw -o - "$manifest" 2>/dev/null)"; do
        echo "    collects ${type#NSPrivacyCollectedDataType}"
        i=$((i + 1))
    done
    i=0
    while type="$(plutil -extract "NSPrivacyAccessedAPITypes.$i.NSPrivacyAccessedAPIType" raw -o - "$manifest" 2>/dev/null)"; do
        reasons=""
        j=0
        while reason="$(plutil -extract "NSPrivacyAccessedAPITypes.$i.NSPrivacyAccessedAPITypeReasons.$j" raw -o - "$manifest" 2>/dev/null)"; do
            reasons="$reasons${reasons:+, }$reason"
            j=$((j + 1))
        done
        list="$list${list:+; }${type#NSPrivacyAccessedAPICategory} (${reasons:-no reason})"
        i=$((i + 1))
    done
    echo "    required-reason APIs: ${list:-none}"
}

# --privacy-report: the archive's manifests, its binary's required-reason APIs, and the way to the
# report itself, which only the Organizer makes.
privacy_report() {
    local target="$1" app candidate manifests info
    [ -d "$target" ] || fail "no archive at $target: make one with Scripts/release-ios.sh (or give an archive's path)."
    app=""
    for candidate in "$target"/Products/Applications/*.app; do
        if [ -d "$candidate" ]; then app="$candidate"; break; fi
    done
    [ -n "$app" ] || fail "$target holds no app under Products/Applications."
    manifests="$(find "$target/Products" -name PrivacyInfo.xcprivacy -type f | sort)"
    say "Privacy manifests in $target (what Xcode's privacy report gathers)"
    if [ -z "$manifests" ]; then
        echo "  none: App Store Connect refuses an upload whose required-reason APIs aren't declared (ITMS-91053)"
    else
        printf '%s\n' "$manifests" | while IFS= read -r manifest; do describe_manifest "$manifest" "$target/Products/Applications"; done
    fi
    check_required_reasons "$app"
    info="$(xcode_version)"
    cat <<REPORT

xcodebuild makes no privacy report: Xcode ${info:+${info%% *} }has no command or option for it (xcodebuild -help);
only the Organizer does. To make the PDF:
  1. open $target      (Xcode shows it in Window › Organizer › Archives)
  2. Control-click the archive › Generate Privacy Report, and save the PDF.
The report lists the same manifests. What they say must agree with App Store Connect's App Privacy
answers (Data Not Collected) and the privacy policy: docs/app-store-metadata.md §4.
REPORT
}

# The exported .ipa, unpacked: an Apple Distribution signature, the app's own identifier, no
# get-task-allow and an App Store profile (all four judged, then every problem named), then
# check_app and the required-reason check. Prints one line with the size, signer and profile.
check_ipa() {
    local ipa="$1" version="$2" build="$3" app details authority entitlements profile name kind expires size value problems=""
    unpacked="$(mktemp -d "${TMPDIR:-/tmp}/sill-ipa.XXXXXX")"
    ditto -x -k "$ipa" "$unpacked"
    app="$unpacked/Payload/Sill.app"
    [ -d "$app" ] || fail "$ipa holds no Payload/Sill.app."
    codesign --verify --strict --deep "$app" || fail "codesign can't verify the app in $ipa."
    details="$(codesign -dvv "$app" 2>&1)"
    authority="$(awk '/^Authority=/ { print substr($0, 11); exit }' <<<"$details")"
    case "$authority" in
        "Apple Distribution: "*|"iPhone Distribution: "*) ;;
        *) problems="$problems"$'\n'"it is signed by '${authority:-nobody}', not an Apple Distribution certificate" ;;
    esac
    entitlements="$unpacked/entitlements.plist"
    codesign -d --entitlements - --xml "$app" >"$entitlements" 2>/dev/null || fail "codesign can't read the entitlements of the app in $ipa."
    value="$(plist_value get-task-allow "$entitlements")" || value=false
    if [ "$value" != false ]; then problems="$problems"$'\n'"it carries get-task-allow, which App Store Connect refuses (a development signature)"; fi
    value="$(plist_value application-identifier "$entitlements")" || value=""
    if [ "$value" != "$team.$bundle_id" ]; then problems="$problems"$'\n'"it is signed as '$value', not $team.$bundle_id"; fi
    profile="$unpacked/profile.plist"
    if [ ! -f "$app/embedded.mobileprovision" ]; then
        name="none"; kind="missing"
        problems="$problems"$'\n'"it has no embedded.mobileprovision"
    elif ! security cms -D -i "$app/embedded.mobileprovision" >"$profile" 2>/dev/null; then
        name="unreadable"; kind="unreadable"
        problems="$problems"$'\n'"security can't read its provisioning profile"
    else
        name="$(plist_value Name "$profile")" || name="?"
        if plist_value ProvisionsAllDevices "$profile" >/dev/null; then
            kind="In-House"
        elif plist_value ProvisionedDevices "$profile" >/dev/null; then
            kind="with a device list (development or ad hoc)"
        else
            kind="App Store"
        fi
        if [ "$kind" != "App Store" ]; then problems="$problems"$'\n'"its profile '$name' is $kind, not an App Store profile"; fi
    fi
    if [ -n "$problems" ]; then
        {
            echo "error: $ipa is not a build App Store Connect takes:"
            printf '%s\n' "${problems#$'\n'}" | sed 's/^/  - /'
            echo "Nothing was uploaded."
        } >&2
        exit 1
    fi
    expires="$(plutil -extract ExpirationDate raw -o - "$profile" 2>/dev/null | cut -c 1-10)" || expires="?"
    size="$(stat -f %z "$ipa" | awk '{ printf "%.1f MB", $1 / 1000000 }')"
    say "Exported $ipa ($size), signed by $authority, App Store profile \"$name\" (until $expires)"
    check_app "$app" "$version" "$build"
    check_required_reasons "$app"
    rm -rf "$unpacked"
    unpacked=""
}

# The Release archive for generic/platform=iOS: signed for development by Xcode's automatic signing
# ($1 = 1), as Product › Archive signs it, or not signed at all ($1 = 0), which needs no
# development certificate or profile: the export signs either the same way (--sign-at-export,
# --unsigned). Checks the archive's version and build and its app, then says $4.
make_archive() {
    local signed="$1" version="$2" build="$3" what="$4" archived_version archived_build identity
    if [ "$signed" = 1 ]; then
        say "Archiving (Release, generic/platform=iOS) into $archive with automatic signing through $signer (log: $out/archive.log)"
        run_logged "$out/archive.log" xcodebuild -project "$project" -scheme "$scheme" -destination 'generic/platform=iOS' \
            -configuration Release -archivePath "$archive" archive -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} \
            || { explain_failure "$out/archive.log" "The archive"; exit 1; }
    else
        say "Archiving without signing (Release, generic/platform=iOS) into $archive (log: $out/archive.log)"
        run_logged "$out/archive.log" xcodebuild -project "$project" -scheme "$scheme" -destination 'generic/platform=iOS' \
            -configuration Release -archivePath "$archive" archive CODE_SIGNING_ALLOWED=NO \
            || { explain_failure "$out/archive.log" "The archive"; exit 1; }
    fi
    archived_version="$(plist_value ApplicationProperties:CFBundleShortVersionString "$archive/Info.plist")" || archived_version="?"
    archived_build="$(plist_value ApplicationProperties:CFBundleVersion "$archive/Info.plist")" || archived_build="?"
    if [ "$archived_version ($archived_build)" != "$version ($build)" ]; then
        fail "the archive is $archived_version ($archived_build), but the project says $version ($build)."
    fi
    check_app "$archive/Products/Applications/Sill.app" "$version" "$build" 1
    identity="$(plist_value ApplicationProperties:SigningIdentity "$archive/Info.plist")" || identity=""
    if [ "$signed" = 1 ] && [ -n "$identity" ]; then
        say "Archived $archived_version ($archived_build), signed by $identity for now; the export signs it for App Store Connect"
    else
        say "Archived $archived_version ($archived_build), $what"
    fi
}

# The line to show when the source isn't committed: a build made from changes nobody can see again.
dirty_warning() {
    if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]; then
        warn "the working tree has uncommitted changes, so this build is not any commit's. Commit first (then --bump) for a build you can find again."
    fi
}

main() {
    local bump=0 upload=0 unsigned=0 sign_at_export=0 print_version=0 report=0 report_archive="" api_key="" api_issuer="" api_key_id=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --bump) bump=1 ;;
            --upload) upload=1 ;;
            --unsigned) unsigned=1 ;;
            --sign-at-export) sign_at_export=1 ;;
            --print-version) print_version=1 ;;
            --privacy-report)
                report=1
                if [ "$#" -gt 1 ] && [ "${2#-}" = "$2" ]; then report_archive="$2"; shift; fi ;;
            --api-key) [ "$#" -gt 1 ] || { usage >&2; exit 2; }; api_key="$2"; shift ;;
            --api-key=*) api_key="${1#*=}" ;;
            --api-issuer) [ "$#" -gt 1 ] || { usage >&2; exit 2; }; api_issuer="$2"; shift ;;
            --api-issuer=*) api_issuer="${1#*=}" ;;
            --api-key-id) [ "$#" -gt 1 ] || { usage >&2; exit 2; }; api_key_id="$2"; shift ;;
            --api-key-id=*) api_key_id="${1#*=}" ;;
            -v|--verbose) verbose=1 ;;
            -h|--help) usage; exit 0 ;;
            *) usage >&2; exit 2 ;;
        esac
        shift
    done
    cd "$(dirname "${BASH_SOURCE[0]}")/.."

    if [ "$unsigned" = 1 ] && { [ "$upload" = 1 ] || [ "$bump" = 1 ] || [ "$sign_at_export" = 1 ] || [ -n "$api_key" ]; }; then
        echo "error: --unsigned makes a build that can't be uploaded; it takes no --upload, --bump, --sign-at-export or --api-key." >&2
        exit 2
    fi
    if [ -n "$api_issuer$api_key_id" ] && [ -z "$api_key" ]; then
        echo "error: --api-issuer and --api-key-id go with --api-key." >&2
        exit 2
    fi

    local version build problem
    version="$(project_setting MARKETING_VERSION)" || exit 2
    build="$(project_setting CURRENT_PROJECT_VERSION)" || exit 2
    if [ "$print_version" = 1 ]; then
        echo "$version ($build)"
        exit 0
    fi
    if [ "$report" = 1 ]; then
        privacy_report "${report_archive:-$archive}"
        exit 0
    fi

    problem="$(xcode_problem)"
    if [ -n "$problem" ]; then
        echo "error: $problem Nothing was built." >&2
        exit 2
    fi
    if [ -n "$api_key" ]; then use_api_key "$api_key" "$api_issuer" "$api_key_id"; fi
    trap cleanup EXIT

    if [ "$bump" = 1 ]; then
        bump_build "$version" "$build"
        build="$(project_setting CURRENT_PROJECT_VERSION)"
    else
        dirty_warning
    fi
    if grep -q 'APP_STORE_URL_PLACEHOLDER' "$links"; then
        warn "$links still says APP_STORE_URL_PLACEHOLDER, so a Mac's update notice shows no App Store link in this build. Once the App Store Connect record exists, put its address there (docs/release-checklist.md, TestFlight)."
    fi

    local info
    info="$(xcode_version)"
    say "Sill for iPhone and iPad $version ($build), $bundle_id, team $team, Xcode ${info%% *} (${info#* })"
    mkdir -p "$out"
    rm -rf "$archive"

    if [ "$unsigned" = 1 ]; then
        make_archive 0 "$version" "$build" "not signed"
        local app="$archive/Products/Applications/Sill.app" ipa="$export_dir/Sill-unsigned.ipa" stage
        check_app "$app" "$version" "$build"
        check_required_reasons "$app"
        rm -rf "$export_dir"
        mkdir -p "$export_dir"
        stage="$(mktemp -d "${TMPDIR:-/tmp}/sill-payload.XXXXXX")"
        mkdir "$stage/Payload"
        ditto "$app" "$stage/Payload/Sill.app"
        (cd "$stage" && ditto -c -k --keepParent Payload payload.zip)
        mv "$stage/payload.zip" "$ipa"
        rm -rf "$stage"
        say "Zipped $ipa ($(stat -f %z "$ipa" | awk '{ printf "%.1f MB", $1 / 1000000 }')): not signed, so it can be neither installed nor uploaded; for looking inside"
        exit 0
    fi

    if [ "$sign_at_export" = 1 ]; then
        make_archive 0 "$version" "$build" "not signed; the export signs it for App Store Connect"
    else
        make_archive 1 "$version" "$build" "signed for development for now; the export signs it for App Store Connect"
    fi

    say "Exporting for App Store Connect ($export_options, destination export) into $export_dir (log: $out/export.log)"
    rm -rf "$export_dir"
    run_logged "$out/export.log" xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_dir" \
        -exportOptionsPlist "$export_options" -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} \
        || { explain_failure "$out/export.log" "The export"; exit 1; }
    [ -f "$export_dir/Sill.ipa" ] || fail "the export succeeded but left no $export_dir/Sill.ipa (see $out/export.log)."
    check_ipa "$export_dir/Sill.ipa" "$version" "$build"

    if [ "$upload" = 0 ]; then
        cat <<NEXT

Sill $version ($build) is exported, signed for App Store Connect: $export_dir/Sill.ipa. Nothing was uploaded.
To send it to TestFlight: Scripts/release-ios.sh --upload (it archives again). Once App Store Connect
has a build $build of $version, the next upload needs --bump.
NEXT
        exit 0
    fi

    local options="$out/ExportOptions-upload.plist"
    cp "$export_options" "$options"
    /usr/libexec/PlistBuddy -c 'Set :destination upload' "$options"
    say "Uploading Sill $version ($build) to App Store Connect with $signer (log: $out/upload.log)"
    rm -rf "$out/upload"
    run_logged "$out/upload.log" xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/upload" \
        -exportOptionsPlist "$options" -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} \
        || { explain_failure "$out/upload.log" "The upload"; exit 1; }
    say "Uploaded Sill $version ($build). App Store Connect processes it (usually 5 to 30 minutes, then an email), and it shows under TestFlight"
    cat <<NEXT

Next (docs/release-checklist.md, TestFlight): internal testers get it once processed; an external
group's first build goes through Beta App Review. The next upload of $version needs --bump.
NEXT
}

# Sourced (to test its functions), the script only defines them.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
