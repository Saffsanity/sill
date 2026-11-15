"""Mutants of Scripts/asc.swift: each changes it in one place, is compiled into .build/checks/asc and
must make run.sh fail (run.sh --binary, so every run of a mutant is under the check's loopback-only
sandbox too). The first 23 are the nightly harness's of 2026-10-29 (PR #246); the rest are What to
Test's rule of 2026-11-09. usage: mutants.py"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "asc", "mutants")
os.makedirs(OUT, exist_ok=True)
source = open(os.path.join(ROOT, "Scripts", "asc.swift")).read()
MUTANTS = [
    # The nightly's harness, 2026-10-29.
    ('public beta without the environment', 'guard environment["SILL_NIGHTLY_PUBLIC_BETA"] == "true" else {', 'guard true else {'),
    ('TRUE counts as true', 'guard environment["SILL_NIGHTLY_PUBLIC_BETA"] == "true" else {', 'guard environment["SILL_NIGHTLY_PUBLIC_BETA"]?.lowercased() == "true" else {'),
    ('every group, external ones too', '    for group in internalGroups {', '    for group in groups {'),
    ('automatic distribution ignored', '        if group.allBuilds {', '        if false {'),
    ('a 30-minute token', '"exp": issued + 15 * 60', '"exp": issued + 30 * 60'),
    ('no kid', '["alg": "ES256", "kid": keyID, "typ": "JWT"]', '["alg": "ES256", "typ": "JWT"]'),
    ('another audience', '"aud": "appstoreconnect-v1"]', '"aud": "appstoreconnect-v2"]'),
    ('a DER signature', 'base64URL(signature.rawRepresentation)', 'base64URL(signature.derRepresentation)'),
    ('the next link followed anywhere', 'guard let linked = URL(string: link), sameOrigin(linked) else {', 'guard let linked = URL(string: link) else {'),
    ('any API base', 'func allowedBase(_ url: URL) -> Bool {\n', 'func allowedBase(_ url: URL) -> Bool {\n    return true\n'),
    ('an approved build submitted again', '        case "READY_FOR_BETA_SUBMISSION":\n', '        case "READY_FOR_BETA_SUBMISSION", "BETA_APPROVED":\n'),
    ('the token printed', '            request.setValue("Bearer \\(bearer())", forHTTPHeaderField: "Authorization")\n',
     '            request.setValue("Bearer \\(bearer())", forHTTPHeaderField: "Authorization")\n            say("token " + bearer())\n'),
    ('no retry after a 429', 'if retryable && attempt < waits.count {', 'if retryable && attempt < 0 {'),
    ('a 5,000-character What to Test', '    let limit = 4000\n', '    let limit = 5000\n'),
    ('INVALID waited on', '            case "FAILED", "INVALID":\n', '            case "FAILED":\n'),
    ('export compliance ignored', '        case "MISSING_EXPORT_COMPLIANCE":\n', '        case "MISSING_EXPORT_COMPLIANCE_NOT":\n'),
    ('any external group is the public beta', '            ?? externalGroups.filter(\\.publicLinkEnabled)', '            ?? externalGroups'),
    ('a 409 on submission fails the job', '            } else if answer.status == 409 {', '            } else if answer.status == 499 {'),
    ('redirects followed', '        completionHandler(nil)\n', '        completionHandler(request)\n'),
    ('What to Test made again over an existing one', 'if let existing = localizations.first(where: { attributes($0)["locale"] as? String == "en-US" }) {',
     'if let existing = localizations.first(where: { attributes($0)["locale"] as? String == "fr-FR" }) {'),
    ('the groups asked for after the wait', '    let groups = listGroups(client, appID: app.id)\n    let internalGroups',
     '    let build0 = waitForBuild(client, appID: app.id, options: options)\n    let groups = listGroups(client, appID: app.id)\n    let internalGroups'),
    ('the version filter dropped', '("filter[preReleaseVersion.version]", version), ', ''),
    ('a 401 retried', 'let retryable = box.error != nil || (box.answer.map { $0.status == 429 || $0.status >= 500 } ?? false)',
     'let retryable = box.error != nil || (box.answer.map { $0.status == 429 || $0.status >= 400 } ?? false)'),
    # What to Test, 2026-11-09: a build that has its own keeps it unless --replace-whats-new.
    ('distribute always replaces (the night of 2026-11-09)', 'setWhatsNew(client, build: build, text: whatsNew!, replace: options.replaceWhatsNew)',
     'setWhatsNew(client, build: build, text: whatsNew!, replace: true)'),
    ('distribute never replaces', 'setWhatsNew(client, build: build, text: whatsNew!, replace: options.replaceWhatsNew)',
     'setWhatsNew(client, build: build, text: whatsNew!, replace: false)'),
    ('distribute replaces unless told otherwise', '    var replaceWhatsNew = false\n', '    var replaceWhatsNew = true\n'),
    ('--replace-whats-new not read', '            options.replaceWhatsNew = true\n', '            options.replaceWhatsNew = false\n'),
    ('--replace-whats-new ignored by the rule', '    if replace { return nil }\n', '    if false { return nil }\n'),
    ('whats-new keeps a build\'s text', 'setWhatsNew(client, build: build, text: whatsNew!, replace: true)',
     'setWhatsNew(client, build: build, text: whatsNew!, replace: false)'),
    ('kept, and written anyway', '        return\n    }\n    if let existing = localizations.first(', '    }\n    if let existing = localizations.first('),
    ('only English (U.S.)\'s text counts', '\n        ?? localizations.first(where: hasWhatsNew)', ''),
    ('another language named before English (U.S.)',
     'return localizations.first(where: { attributes($0)["locale"] as? String == "en-US" && hasWhatsNew($0) })\n        ?? ',
     'return '),
    ('white space counts as text', 'return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty', 'return !text.isEmpty'),
    ('an empty localization counts as text', 'return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty', 'return true'),
    ('no text at all (null) counts as text', 'guard let text = attributes(localization)["whatsNew"] as? String else { return false }',
     'guard let text = attributes(localization)["whatsNew"] as? String else { return true }'),
    ('--replace-whats-new let through with whats-new', 'if options.replaceWhatsNew && options.command != "distribute" {',
     'if options.replaceWhatsNew && options.command == "groups" {'),
]
binary = os.path.join(OUT, "asc")
caught = 0
for name, old, new in MUTANTS:
    if source.count(old) != 1:
        print('STALE (pattern found %d times): %s' % (source.count(old), name))
        continue
    path = os.path.join(OUT, 'asc.swift')
    open(path, 'w').write(source.replace(old, new))
    if os.path.exists(binary):
        os.unlink(binary)
    build = subprocess.run(['swiftc', '-O', '-o', binary, path], capture_output=True, text=True)
    if build.returncode != 0:
        print('NO BUILD: %s\n%s' % (name, build.stderr[:600]))
        continue
    run = subprocess.run(['/bin/bash', os.path.join(HERE, 'run.sh'), '--binary', binary], capture_output=True, text=True)
    last = (run.stdout.strip().splitlines() or ['?'])[-1]
    if run.returncode != 0:
        caught += 1
        print('caught: %s (%s)' % (name, last))
    else:
        print('SURVIVED: %s' % name)
print('%d of %d mutants caught' % (caught, len(MUTANTS)))
sys.exit(0 if caught == len(MUTANTS) else 1)
