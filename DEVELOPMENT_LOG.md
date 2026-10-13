# Development log

## Initial inspection — 2026-10-13

- Clean main branch at a79d139; only existing file is GPLv3 LICENSE, preserved.
- Host: Linux x86_64. No preinstalled Swift, Xcode, FFmpeg or FFprobe. Native app, Mach-O, DMG, signing and Sonoma runtime cannot be verified here.
- Git user.name and user.email are unset. Commits require the user’s real identity; no fabricated author or global configuration changes.
- Applicable engineering, Git, code review and native UX skills read. Design search returned web-oriented neumorphism: rejected for this native utility; use standard macOS controls, system typography, sidebar and clear status labels.
- Independent core, native UI and macOS build infrastructure development in progress.
- No remote push, Actions run or release publication authorized/performed.

## Verification ledger

- Initial portable packaging suite: 6 Python unittest tests passed (version comparison, fail-closed guard, Xcode scheme XML and PNG CRC/decompression). Shell syntax and Python compilation checks passed.
- Core agent reports Swift 6.0.3 strict language mode compiled on Linux: initial 10, expanded 13 and then 17 XCTest tests passed. Tests perform real FFmpeg conversion, corrupted input rejection, pipe saturation, SIGTERM escalation, deadlines, concurrent output collision, cancellation cleanup and audio/target-size verification. Tools are FFmpeg 7.0.2 test-only GPL outside repository, not the release FFmpeg 8.0.1 LGPL configuration.
- Parent ran 4 actual XCTest scanner tests: recursive/nonrecursive Unicode import, hidden files, symlinks, missing/remote URLs and image recognition passed.
- Parent packaging suite expanded to 8 passing tests including wrong architecture, excessive minimum OS and escaping symlink rejection using mocked tool output (not actual Mach-O verification).
- Native Swift parser initially caught an unterminated diagnostics string; repaired by app agent. Subsequent actual Swift6 frontend syntax parse passed. This does not typecheck Apple frameworks.
- Independent review identified and prompted fixes for manual-probe scheduling, quit/import task tracking, corrupt-state overwrite risk, M4A muxer mapping and hidden audio controls.
- CI/build infrastructure implemented and statically validated, not executed on macOS. App/resources/catalog/localization implemented. Additional ImageIO integration and persistence tests underway.
- Native UI, both macOS architecture builds, DMG mounting, signing/notarization and Sonoma runtime remain unverified.
- Initial scoped commit attempted and failed with Git exit 128: missing author identity. No new commits created.

## Verified follow-up — 2026-10-13

- Parent independently ran strict Swift6.0.3 full suite with Debian FFmpeg/FFprobe5.1.9 extracted only under /tmp: 25 core tests passed in final independent parent run05:32:55; all18 profiles actually converted and output probed. Separate ImageIO platform test explicitly skipped (26 total,1skip,0fail). Default aspect-fit/padding is validated with decoded RGB border pixels and explicit-stretch argument/Codable tests. Debian test tools are GPL-enabled and never shipped; macOS8.0.1 LGPL configuration remains separately untested.
- Static FFprobe7.0.2 and alternate snapshot crashed on valid MPEG-TS; raw CLI reproduction confirmed tool issue. Replaced test pair with Debian5.1.9 rather than hiding failure or skipping format. Test-generated ELF core dump verified then removed; future dumps ignored and test commands disable core dumps.
- Parent fixed long conversion progress memory capture: progress streaming is not accumulated as output;9MB streaming regression passed. Captured diagnostic stdout overflow still fails explicitly.
- Real app persistence5/5 and scanner4/4 remain passing; packaging8/8, YAML matrix/release barrier parsed with installed Node YAML (Python PyYAML absent). Native source/test syntax parsed with actual Swift compiler.
- App gains per-job output folder snapshots, requested profile catalog, image quality/alpha warnings, configurable history retention, bounded metadata tasks and forwarded image-worker cancellation.
- macOS-only model5 tests and ImageIO6 tests are added, not executed here. macOS-compatible build guards correctly reject Linux.

## Goal round1 — durable recovery and loader checks

- Queue is now persisted in additive schema1 snapshots, restoring pending jobs paused and interrupted active jobs failed for manual retry. Output paths remain available for inspection. Admission/decode/save enforce10000 unique job IDs.
- Parent independently reran portable persistence7/7, scanner4/4 and packaging9/9 on Linux. Native source/test syntax parse passes; six app model tests await macOS execution.
- Corrected bundle verifier `@executable_path` resolution to the actual process root rather than loaded-library directory. Regression covers app and independent FFmpeg executable roots, loader-relative paths and escaping/unapproved paths. This is a simulated filesystem test, not native Mach-O execution.
- Added visible FFmpeg LGPL attribution and corresponding-source/license folder access in diagnostics.
- Exact-source Linux FFmpeg8 compilation delegation failed before starting; no build or verification claim is made. No background jobs remain from that attempt.

## Goal round2 — bounded import and private state

- Recursive scanner now deduplicates and excludes already-queued paths before admission, and stops at remaining queue capacity rather than accumulating an unbounded list. Parent scanner5/5 tests pass, including zero-capacity and duplicate inputs.
- State directory/file and corrupt recovery backup use0700/0600 permissions. Parent persistence8/8 tests verify those modes, symlink rejection and the32MiB read guard without modifying rejected input.
- Native settings draft now accepts odd image bounds while retaining even video dimensions; portable draft regression passes. Parent independently verified final core27/27 and all18 profiles using Debian5.1.9 test tools. PNG/JPEG/WebP actual7x5 outputs were converted, probed and decoded; a YUV chroma/padding rounding failure was fixed by RGB intermediate filtering for resized images. Video alignment remains unchanged. One macOS ImageIO test is explicitly skipped (28total,1skip,0fail). Localization comparison confirms205 unique entries per table and coverage of every app L key.

## Goal round3 — release version consistency

- Found that tag archives could advertise a new release while app Info.plist remained1.0.0. Added shared release-version parser, CI resolves the tag once, build-app passes parsed MARKETING_VERSION to Xcode, and package rejects app/release version mismatch before publishing artifacts.
- Added three portable tests for normal/tag/prerelease versions, malformed input and actual temporary plist mismatch. Python suite12/12 passes; scripts compile/syntax-check; workflow YAML parses with both architecture matrix and full-build release barrier intact. Native Xcode execution remains unavailable.

## Goal round4 — engine/source pin consistency

- Bundle checks now require both actual FFmpeg/FFprobe runtime version strings to equal the source pin, not merely a matching source archive. Shipped ffmpeg.env must match build pin exactly.
- LGPL isolation checks parse complete flags rather than accepting substring lookalikes; unapproved enables remain rejected. Verifier child commands have60-second deadlines.
- Added runtime-version, configuration-token and subprocess-deadline regression tests. Portable Python suite15/15 passes. These checks do not substitute for native bundle execution; macOS CI remains unexecuted.

## Goal round5 — progress and retry state

- Progress parser accepts only known fields, ignores nonfinite timestamps, avoids nonfinite fractions and recovers after oversized incomplete lines. New malformed-data regression passes along with chunk-boundary parsing.
- Retry clears old start time, progress details, metadata/image inspection, cancellation state and size deviation while preserving conversion settings. Native model regression assertions are added and syntax-parsed, not executed without macOS.
- Parent full strict Swift6 test run:28core passes; all18 profiles converted;1ImageIO platform skip (29total,1skip,0fail).

## Goal round6 — staged publication safeguards

- Shared publication now rejects nonlocal/same-path sources, symlink staged files and empty/nonregular staged output. Naming skips dangling destination symlinks; exclusive publication still protects against concurrent collisions. These checks are defense-in-depth within private job directories, not a claim of protection against a malicious same-user filesystem race.
- New actual filesystem test preserves dangling links/targets and staged bytes; targeted naming/publication tests pass. Parent full suite29core passes, all18 real conversions remain passing;1ImageIO platform skip (30total,1skip,0fail). macOS exclusive-rename behavior still needs native execution.

## Goal round7 — localization and saved image settings

- Added permanent Python CI tests checking every native literal L/NSLocalizedString key is covered by both tables, keys are identical, entries nonempty, and malformed/duplicate entries fail.205 existing entries pass; portable Python suite17/17.
- NativeImageOptions decoding supplies legacy defaults and rejects quality outside0.1...1 before percentage rendering/slider use. Portable persistence9/9 tests pass with invalid and boundary-quality regressions. Native app syntax parse passes; no Apple module/runtime claim.

## Goal round8 — actionable engine and signing failures

- Capability discovery now reports stderr/exit status from the command that actually failed rather than always reporting encoder output. Regression launches a temporary executable three times to fail version/encoder/muxer independently; targeted Swift test passes. Full-core count is not updated until full rerun.
- Secretless signing fallback now requires every Apple secret absent. A stray password/notary credential cannot silently downgrade a misconfigured signed release to ad-hoc. Two portable tests execute actual script guard branches (all6 single-secret failures and clean secretless success), without invoking Apple security APIs. Python19/19 passes; shell syntax passes.

## Goal round9 — process launch preconditions

- ProcessRunner rejects nonlocal executable URLs and invalid/nonfinite/nonpositive/excessively large deadlines before launching any child; nil deadline retains explicit unlimited conversion behavior. Cancellation check runs before validation.
- Actual temporary-file regression confirms rejected requests never launch touch, while nil deadline launches successfully. Existing termination deadline test passes. Full strict Swift6 integration31core tests pass, all18profiles converted;1ImageIO platform skip (32total,1skip,0fail).

## Goal round10 — persisted queue local paths

- State validation rejects nonlocal source/output/destination URLs in queue snapshots and nonlocal global output directory before restoration; applies to decoding and saving. Existing nullable/legacy per-job paths remain accepted.
- Four actual encode/decode regressions cover remote source, per-job destination, output and global destination; valid local snapshot still passes. Portable persistence10/10 and native source syntax parsing pass; this is not native relaunch verification.

## Goal round11 — reproducible verification entry point

- Added verify-development.sh combining required-engine integration, scanner/persistence tests, Python tests, shell/Python syntax and native source parsing. Explicit absolute executable paths required; missing-engine guard actually exits1 rather than silently skipping.
- Parent ran complete script successfully with extracted Debian test engines:31core passes plus1explicitImageIOskip, scanner5/5, persistence10/10, Python19/19, parse/syntax/whitespace checks. Script prints platform boundary and does not call Linux success native macOS readiness. README documents one reproducible entry point rather than relying on optional swift-test skips.

## Goal round12 — stable persisted list identities

- State decoding/saving rejects duplicate history and preset IDs as well as queue IDs, preventing ambiguous SwiftUI list identity on restored corrupt state. Duplicate display names remain valid when IDs differ.
- Portable persistence11/11 passes; regression checks duplicate history/preset roundtrip rejection and legitimate same-name distinct-ID presets. Native list rendering remains untested without macOS.

## Goal round13 — atomic preset edits

- Found preset edit changed name/profile before throwing draft validation, leaving partially mutated unsaved UI state. Validation now precedes all mutations.
- Added native model regression asserting invalid edit preserves name/profile/settings and stored bytes. Seven native model tests now syntax-parse; none executed here. Portable persistence11/11 rerun passes; native behavior still needs Apple SDK test runner.

## Goal round14 — probe frame-rate validation

- Replaced compactMap rational decoding, which could turn malformed24/junk/1 into24/1, with exact two-component finite/positive validation. Nonfinite, empty, zero-denominator, negative and overflow ratios are unavailable rather than propagated as valid metadata.
- Targeted strictSwift6 regression passed valid30000/1001 and24/1 plus15malformed boundary inputs. Full integration count remains31until rerun; native UI verification still unavailable.

## Goal round15 — metadata inspector and complete rerun

- Native file inspector now exposes existing verified frame-rate and bitrate metadata with localized units and guarded invalid values. Swift syntax parsing and localization coverage pass; actual layout/VoiceOver requires macOS.
- Full unified verification rerun passes32core, scanner5/5, persistence11/11 and Python19/19; all18profiles really converted,1ImageIO platform skip (33total,1skip,0fail). This also covers latest rational parser change; seven native model tests only syntax-parsed.

## Goal round16 — saturated failure diagnostics

- Added actual child-process regression emitting9MB stderr followed by a final failure explanation and exit7. Runner completes without deadlock, bounds diagnostic tail at8MiB and preserves final error text. Targeted strictSwift6 test passes; full suite count remains32until rerun.
- This extends stdout/dual-pipe coverage without changing subprocess lifecycle code; native Darwin pipe behavior remains a separate macOS gate.

## Goal round17 — strict portable app typechecking

- Scanner and persistence harnesses now typecheck actual portable app sources in Swift6 before linking legacy Swift5 XCTMain harness. This closes the prior strict-language coverage gap for AppPersistence/SettingsDraft/UserErrors/BuiltInPresets/ImportScanner; Apple-framework branches still require macOS SDK.
- Strict checks and actual portable persistence11/11/scanner5/5 pass.
- Independent official pinned8.0.1 LGPL Linux test-engine source build requested under/tmp; configured and compilation log exists, but managed job bash-198 is unknown in both parent and child registries. Agent is inspecting processes before any incremental restart; not complete at this ledger update. No claim it verifies release/macOS configuration.

## Goal round18 — executed preset catalog verification

- Portable harness now links actual BuiltInPresets alongside persistence sources. New test checks all12built-ins validate, IDs unique, no unverified/empty engine enables presets, Universal H264 refuses MPEG4-only capabilities, compact softwareMP4 works, absent MP3 encoder disablesMP3. Actual strict checks and12/12XCTest pass.
- Agent confirmed prior make stopped (no live compiler via/proc and wait-no-child log); recovery is incremental foreground make, no concurrent duplicate. Native LGPL engine verification still pending artifacts.

## Goal round19 — notarization preflight before secret import

- Full notary credential tuple is now validated before randomness generation, certificate decoding and keychain import. Previously partial notary fields failed after creating/importing signing keychain. No Apple security API claim; four real shell guard regressions verify rejection before certificate processing/add-mask.
- Python20/20, shell syntax and whitespace checks pass. LGPL source build still owned by agent, no duplicate compilation started.

## Goal round20 — literal process argument safety

- Real child opens a file with Cyrillic, spaces, semicolon, shell substitution syntax and newline in its filename through ProcessRunner argument array; returned bytes match original and folder has no additional files. Targeted strictSwift6 regression passes, no shell used.
- Pinned8.0.1 ffmpeg artifact now exists; agent still verifying pair/runtime/conversions. Existence alone not recorded as successful engine verification. Full previous count32unchanged until complete rerun with latest tests.

## Goal round21 — target budget byte boundary

- Rejected sub-byte target sizes before Int64 truncation, which could previously yield zero targetBytes for positive sub-byte size with tiny duration. Existing budget regression now verifies sub-byte rejection and exact1byte boundary acceptance; strictSwift6 test passes. Exact output-size guarantee not implied.
- Both pinned-engine executables now exist; delegated conversion verification still pending; no compile/existence-only runtime claim.

## Goal round22 — pinned LGPL8.0.1 runtime verified

- Agent completed official source build under/tmp after safe incremental recovery; parent independently confirmed ffmpeg/ffprobe8.0.1 and LGPL2.1+ runtime. Static FFmpeg/zlib, libc/libm system dependency, network disabled. Archive hash matches Config/ffmpeg.env. Linux minimal test config, NOT shipped shared macOS config.
- Initial full run exposed unguarded optionalWebP in odd-image test. Corrected capability gating: PNG/JPEG required, absent optionalWebP printed explicitly. Parent full unified script against LGPL8.0.1 passes34core,1ImageIOskip, scanner5, persistence/presets12, Python20. All13available profiles really trimmed/scaled/validated; absent webm/mp3/ogg/opus/webp explicitly listed, not claimed tested.
- Parent independently reran full core using Debian GPL5.1.9 test-only tools:34passes1ImageIOskip, all18profiles converted includingWebP odd7x5. Neither engine is distributed as app artifact; native Xcode/VideoToolbox/ImageIO/bundling/ZIP/DMG gates still outstanding.

## Goal round23 — complete release artifact gate

- Added strict verification of both architecture artifact sets before tag publication: exact4manifest entries, nonempty regular files, hashes, version/architecture status match, known signing/notary values and no ad-hoc notarization claim. Rejects empty/partial/duplicate/path-escaping manifests. Release job checks out verifier and runs gate; no remote release or Actions triggered.
- Five new simulated artifact tests pass (Python25/25), YAML parsed and actual gate wiring checked. Synthetic file bytes are deliberately not claimed real ZIP/DMG. Native package verifier remains required upstream. Host still Linux with no Xcode; git author name/email absent.

## Goal round24 — bounded release metadata before hashing

- Checksum/status metadata must be regular nonsymlink files bounded64KiB. Removed earlier unrestricted sha256sum invocation in release job; strict name validation now happens before any artifact hashing. Streaming1MiB hashing avoids Python3.11-only file_digest, supports older macOS Python.
- Added actual symlink/oversize manifest regression, Python26/26 passes. No native package or remote-release claim.

## Goal round25 — preserved source audio is mandatory

- Output validation now rejects a converted video lacking audio when source contains audio and removal was not requested. Previously audio codec was checked only if output stream happened to exist. Silent inputs and image extraction do not require audio.
- Missing/present/silent metadata regression added; full unified pinnedLGPL8.0.1 suite passes35core+1ImageIOskip, scanner5/5, persistence/presets12/12, Python26/26.13supported profiles converted; five optional codecs explicitly absent. Native release gates remain outstanding.

## Goal round26 — requested frame-rate validation

- Output video FPS is now checked when user requested a frame rate, with small rational representation tolerance. Missing/nonfinite/mismatched rates rejected; audio/image outputs do not apply this gate.
- Actual LGPL8.0.1 conversions24fps and30000/1001fps pass with retained audio. Separate nil/30/nan/inf output metadata rejection regression passes. StrictSwift6 compile and whitespace pass. Last full suite count35until rerun.

## Goal round27 — no silent bypass of duration verification

- When expected duration is known, nonimage output must report finite positive duration within tolerance; nil duration previously skipped requested trim verification. Unit regression covers nil/zero/negative/mismatch/nan/inf.
- Complete LGPL8.0.1 unified script passes38core,1ImageIOskip, scanner5, persistence/presets12, Python26. All13supported profiles and latest integer/fractionalFPS tests pass. Five optional codecs unavailable explicitly.

## Goal round28 — complete decoding before publication

- Added full staged-file FFmpeg null decode with xerror/err_detect explode and explicit video/audio mapping before exclusive publication. Cancellation awaits decoder process; metadata alone no longer establishes output integrity. Extra full pass increases conversion time, not described as free. CLI consulted current FFmpeg docs and real8.0.1 command verified.
- Corrupt-media real decoder rejection test added. Full LGPL8.0.1 unified suite39core passes1ImageIOskip, scanner5, persistence12, Python26. All13available output profiles pass production decode gate. Native macOS decoder/runtime gate outstanding.

## Goal round29 — optional formats decode gate verified

- Parent full Debian test-only integration rerun39passes1ImageIOskip covers all18profiles through newly added production full-decode gate, including optionalWebM/MP3/OGG/Opus/WebP. Does not validate those encoders in minimal LGPL release.
- New targeted decoder-cancellation test confirms cancellation before launch wins even when executable does not exist. Passes strictSwift6; latest added test not yet in full-count39. Pinned verification report updated to latest complete39/Python26 evidence rather than original34/20 snapshot.

## Goal round30 — explicit PNG system dependency

- Upstream8.0.1 configure inspection confirms PNG selects inflate/deflate wrapper requiring zlib; isolated release disable-autodetect needs explicit enable-zlib. Added system SDK zlib flag (no Homebrew), bundle gate now requires png/mjpeg encoders as well as AAC/VideoToolbox.
- Portable flag regression+Python27/27, shell syntax, whitespace pass. Existing Linux LGPL source-build already had explicit zlib and PNG conversions succeed; this does NOT prove macOS SDK linkage. Actual macOS build remains required.

## Goal round31 — no unchecked wildcard upload assets

- Release gate rejects any MediaForge-* file not belonging to exact validated two-architecture set (including checksums). Prevents wildcard gh-upload from publishing stale/unverified extra assets despite validated expected files.
- Real temporary-directory stale ZIP regression added, Python28/28 passes. No GitHub action or release was executed.

## Goal round32 — history action URL boundaries

- Restored history source/output/destination URLs now must be local, same boundary already applied to queue. Prevents persisted nonlocal output reaching native open/reveal and repeat conversion actions. Nullable legacy outputs preserved.
- Three actual encode/decode validation failures and valid-local regression pass; strictSwift6 checks and portable persistence/presets13/13 pass. Native Finder actions remain unverified.

## Goal round33 — decoder-stage failure transaction

- New actual pipeline test runs officialLGPL encoder/probe through executable wrapper, injects exit7 only at xerror decode stage, confirms stage reached, no published output, original bytes unchanged and private job directory removed.
- Initial fixture failed early because SwiftJSON escaped slashes are not Python string path syntax; exposed diagnostics, fixed JSONEncoder withoutEscapingSlashes, reran targeted regression successfully. Full suite count39not updated until full rerun.

## Goal round34 — bounded actual state reads

- StateStore reads at most32MiB+1 through FileHandle and checks actual bytes, rather than relying only on attributes then unbounded Data(contentsOf:). Retains regular-file precheck and rejects oversized actual reads. Defense against growth after attribute check, not malicious same-user path race-proof claim.
- StrictSwift6 actual persistence source checks and13/13portable tests pass including oversized/symlink/roundtrip/quarantine regressions; native relaunch remains unverified.

## Goal round35 — shipped decode-verification prerequisites

- Native bundle gate now checks H264/HEVC/AAC/PNG/MJPEG/MPEG4 decoders and null muxer in actual shipped engine, not just encoders. Necessary for added full-output decode check; missing components fail packaging instead of first user conversion.
- Portable source-wiring guard test plus existing simulated verifier tests pass29/29; actual decoder list check on macOS still not executed, no native bundle acceptance claim.

## Goal round36 — executed decoder table validation

- Replaced source-string assertion with real callable decoder/muxer gate tests. Gate parses FFmpeg component name columns rather than accepting name mentions in descriptions; missing each required decoder and spoofed null text reject.
- Python29/29 and gate against actual Debian FFmpeg decoder/muxer output pass. Does not claim Darwin bundle pass.

## Goal round37 — exact encoder table validation

- Encoder gate now uses same actual codec-name parser as decoders. Required codec mentioned only in description cannot falsely pass; GPL encoder detection uses actual name instead of substring false positives. License configuration gate unchanged.
- New executed parser regression tests remove each required codec and insertGPL/mock descriptions; Python30/30passes. Native bundle gate execution still macOS-required.

## Goal round38 — require nonempty decoded streams

- Reproduced pinnedFFmpeg success0 for header-only WAV full decode. Added abort_on empty_output_stream after current docs+actual CLI verification (empty now exit234). Production verifier rejects zero decoded packets/frames; real empty-WAV regression passes.
- Complete unifiedLGPL suite42core passes1ImageIOskip, scanner5, persistence13, Python30;13profiles converted. Includes decoder-stage transactional failure and cancellation tests added since last full39run.

## Goal round39 — fail-fast capability discovery

- Capability discovery checks each command immediately instead of launching encoder/muxer queries after a failed version/encoder command. Preserves real failing-stage stderr while avoiding further startup delays from a broken executable.
- Actual executable regression logs invocations:versionfailure1call, encoderfailure2calls,muxerfailure3calls. Targeted strictSwift6 passes. Independent read-only native compiler/API audit delegated, pending; not Apple SDK verification.

## Goal round40 — duplicate native entry-point exclusion

- Independent audit found Resources/Verification/ImportScannerChecks.swift @main inadvertently included through synchronized Resources app group. App already has @main; excluded Verification subtree in app target membershipExceptions to avoid duplicate entry-point build failure and shipping test harness.
- Source membership guardPython31/31 and native syntax parse pass. This is a concrete project-config correction but no Xcode compile proof on Linux. Xcode scheme has build targets only; actual model/ImageIO tests run via Swift package in CI, not xcodebuildtest.

## Goal round41 — history retention UI persistence

- Native settings view now persists historyLimit changes immediately; previously lacked onChange handler so idle quit lost retention setting/trimming. Added native model trimming/store regression; eight native tests syntax-parse only, portable state13/13passes.
- Independent native audit complete: confirmed corrected resource duplicate-main exclusion, package test vs assembled .app semantics documented. Found remaining user-visible batch-pause behavior and native-image-only controls visible for video JPEG; follow-up required, not silently called productioncomplete. No evidence of additional actual Swift6 compiler defects without Apple SDK.

## Goal round42 — freeze retry/replay during termination

- retry and repeatConversion now reject mutations once termination begins, matching import/start guards. Prevents altering queue/state snapshot during shutdown; scheduler already blocked engine starts, so not a runaway-process fix.
- Expanded native termination regression checks status/count/persistedbyteidentity after retry/replay; syntaxparse only on Linux. Portable persistence13/13 and diffcheckpass; native runtime test pending.

## Goal round43 — explicit JPEG control scope

- Added always-visible Russian/English inline explanation adjacent to JPEG controls:quality/background apply only to source images via ImageIO, not video-frame export. Keeps preset editing useful without pretending FFmpeg applies native options.
- Localization parity/allliteralkeys and Python31/31, Swift syntaxparse, whitespace pass. No screenshot/layout/VoiceOver verification on macOS. Targeted UXsearch initialmatch off-topic; retried narrower inlineformquery, does not constitute platform verification.

## Goal round44 — announce intentional queue changes pause

- New imports/retries/history replays keep manualStart policy to recheck capabilities/loss consent. Existingbatchpause now explicitly alerted/logged inRU/EN; activejobs keep running. Empty/duplicate-only import no longer pauses batch. Does not auto-start newly added images bypassing warnings.
- Added native retry/replay paused-state+notification regression (9native tests syntaxparse only). Python/localization31/31/diffcheck pass; actual scheduler native-runtime coverage still pending.

## Goal round45 — full eighteen-profile regression recheck

- Full unified verification using Debian5.1.9testonlyGPL engine passed42coretests with all18actualconverted profiles,1explicitImageIOskip, scanner5,persistence13,Python31. Includes abort_on empty_output_stream and failfastcapability changes. Engine not shipped. NativeUI nine tests remain syntaxonly.
- Rechecked Git author via gitvar:exit128identityunknown; onlyInitialcommit exists. Cannot fabricate author, no remoteoperations. Native CI does invoke macOS SwiftPM app tests alongside real Xcodeappbuild; hostcannotexecute those gates.

## Goal round46 — directory symlink/cycle import boundary

- Added actual filesystem scanner test selecting directory with external-directory symlink and self-cycle. Verifies neither traversal outside selected folder nor cycle duplication, including strictlimit1 and explicitlyselectedlink. Existing source already passes; no speculative production rewrite.
- StrictSwift6scanner source check and6/6actualportableimporttests pass. Darwin FileManager traversal still independently tested by CI.

## Goal round47 — bounded core history reads

- HistoryStore (separatelytestedcoreprimitive, not appStateStore) now rejects nonregular inputs and reads at most32MiB+1 then checks actual bytes, matching bounded app state read. Attribute growth no longer causes unlimited Data read; not malicioussameuserTOCTOUproof.
- Twoactualhistorytests pass with strictSwift6, including sparseoversizedfile/symlink/directory rejection and unchangedsource/link plus preservedcorruption. New43rdcoretest targetedonly; previousfull42count retained.

## Goal round48 — await actual model import regression

- Added modelwaitForImport awaiting managedtask completion (no sleep/poll). NewmacOS test imports actualfiles and checks settings/profile snapshot beforeUIchanges, dedupe, savedoutputdirectory, newtaskpausefeedback and duplicateonlyimport preservingbatchstate.
- Tenth native modeltest syntaxparsednotexecutedonLinux; strictportable scanner6/6passes. Native compiler/runtime CI still required; no assertion of fullmodelverification.

## Goal round49 — actual native serial scheduler test added

- ForgeModel accepts explicit optional injected toolchain for tests; defaultproduction still bundleddiscoveryonly. Added waitForQueue awaiting actual managed tasks/rescheduledtasks, not polling.
- Native test generates realWAV, prepares actualengine, starts3FLACjobs withlimit1, assertsinitial1active/2pending, awaitsbatch, probes3uniqueoutputs, checksstate/history/originalbytes. Eleventh native test syntaxonly here; CI passes explicitbundledtoolpaths and requiresintegration, so will exercise it onmacOS. Portable persistence13/13passes. No claim nativequeue runtimepassed.

## Goal round50 — engine preparation shutdown guards

- prepare/refreshEngine reject aftertermination; preparation completing late cannot setengineReady. Expanded native terminationtest verifies no new diagnostics/readytransition when prepare/refresh called aftercancelAndWait. Native syntaxonly; in-flight capabilityprocess cancellation notyetmanagedbyshutdown.
- Full pinnedLGPL8.0.1 unifiedrun passes43core+1explicitImageIOskip,6scanner,13persistence,31Python. Nativeapp11/ImageIO6 runtime andAppleSDKtypechecking unverified.

## Goal round51 — managed capability-check shutdown

- Capability discovery now trackedTask, parentcancellation forwarded, shutdown cancels and awaits capabilityresult as well as conversion/importtasks. Refresh rejects concurrentcheck. Latecancelerrors cannot update readiness/diagnostics duringtermination; finalshutdown setsenginereadyfalse andpersists evenidlehistorysettings.
- Native Swift syntax andportablepersistence13/13pass; in-flightmacOScapabilityshutdown runtime still needs focusedtest, no proofclaimed. ProcessRunner cancellation itself separatelyverified.

## Goal round52 — native failed capability refresh regression

- Added native modeltest usingactualexecutable exits17+stderr to verify readinessfalse, diagnostics, prepareonce, explicitrefresh retries, noqueueautostart and refreshblockedaftershutdown. Twelfth native test syntaxonly; actualmacOSexecution pending. Does not cover in-flight cancellation handshake yet.
- Portableactual capabilityfailure regression passes; Swift6corecompiled, native syntax/diffcheckpass.

## Goal round53 — cancelled capability state recovery

- Cancelledmodelpreparation now resets prepared/ready/capabilities so task cancellation does not permanently suppress future prepareattempt. Keeps cancellation distinct fromenginefailure diagnostics. Native syntaxonly; managedshutdownstillguarded.
- Added actualcore cancellation-before-capability regression using executablemarker:pre-cancelledtask throwsCancellationError andneverlaunches child. StrictSwift6targetedpass, full44core notyet rerun.

## Goal round54 — readiness cancellation handoff

- Task cancellation checked after awaited capabilityresult before publishingready, closing success/cancelhandoff. Native recoverytest now precancels preparation, checks noerrordiagnostics, then retries actualfailingexecutable to prove preparedreset (syntaxonlyhere).
- Full pinnedLGPLunifiedrun44corepasses+1ImageIOskip, scanner6,persistence13,Python31. Nativeapp12 runtime stillrequired.

## Goal round55 — existing app state directory privacy

- Newtest reproduced755existingstatedirectory retained despitecreateDirectory700attributes (1failure). Save now verifiesreal-directorytype andexplicitlysets700 before atomicwrite; defaultdedicatedMediaForgedirectoryprivacyrepaired. Injectedstoreparent also becomesprivate; callersmustuse dedicateddirectory.
- StrictSwift6actualpersistence14/14 rerunpasses afterfix, diffcheckpass. No malicioussameuserpathraceproofclaim; native filesystempermissions stillneedsDarwinrun.

## Goal round56 — state directory symlink preservation

- Added realfilesystemregression for symlinked immediateStateStoreparent:save rejects, targetstatebytes/755permissions/linkdestination unchanged. Existing directorytypeguard passes without rewrite. Intermediateancestor maliciousraces notclaimedsafe.
- StrictSwift6portable persistence15/15pass; Darwin behavior CIneeded.

## Goal round57 — active capability subprocess cancellation

- Added realexecutable capabilitytest with FIFOreadinesshandshake (no sleep/poll). ChildignoresSIGTERM, signalsready, thenblocks; testcancelscapabilitytask and awaitsCancellationError. Invocationlog confirms onlyversionquery and noencoder/muxerqueries; ProcessRunnerkill escalation needed.
- StrictSwift6targetedtestpasses1.792sec. 45thcoretest notfullrerunyet; appmanagedtaskshutdown stillrequiresnativeexecution.

## Goal round58 — native active capability shutdown test

- Added13thnative modeltest withFIFOhandshake:actualcapabilitychild ignoresTERM/signalsready, cancelAndWait must stopit, preparationawaits, checksonequery/noready/nocapabilities/nodiagnostics and persistedstate. No sleeps/polls; failure readerdeadline prevents unboundedhandshake. Native syntaxonlyhere; matchingcorefixture alreadypassed.
- Full pinnedLGPLunifiedrun45corepasses+1ImageIOskip, scanner6,persistence15,Python31. No AppleSDK/native runtime/artifactclaims.

## Goal round59 — cancel all tasks before awaiting cleanup

- Shutdown snapshots imports/scanner/conversions then cancels all beforefirstawait. Activeencodes no longer continueuncancelled while awaitingscannercleanup. Managedcapability alreadycancelledfirst.
- Added14thnative test immediateimport→shutdown checks noqueuepublication and persistedemptyqueue; syntaxonlyonLinux. Portable scanner6/6pass; native scheduler/runtime pending.

## Goal round60 — probe cancellation before filesystem work

- MediaProbe.inspect checks cancellation before URL/attributesvalidation, matchingProcessRunner/decodegate policy. A queued cancelledjob withremovedsource now endsCancelled instead offilemissingfailure; avoidsneedlessfilesystem/probework.
- New46thcoretest uses missinginput/toolpath and pre-cancelledtask, confirmsCancellationError, strictSwift6targetedpass. Fullcountstill45untilrerun.

## Goal round61 — normalized output reservations

- Actual regression reproduced reservednested/../candidate ignored by rawURLSet, choosing same standardizedoutput (2assertionfailures). Normalize reserved/candidateURLs for naming; exclusivepublication remainslastlineofsafety.
- Bothnaming/exclusivecommit tests passafterfix withSwift6. New47thcoretest targetedonly; symlink/casefoldfilesystemaliases notclaimed solved.

## Goal round62 — long Unicode result filenames

- Realfilesystemregression reproduced valid250byteASCIIsource basename→265/267bytegeneratedoutput causingENAMETOOLONG afterconversion. SuggestedURL now budgets255UTF8bytes includingcollision suffix/ext, truncates atCharacterboundaries andfallbackmedia foroversizedfirstgrapheme. Shortnamesunchanged.
- LongASCII/Cyrillic publication/originalpreservation and2existingnamingtests passSwift6. New48thcoretest targetedonly. Stricterexternalfilesystemlimits stillfailhonestly; no universalfilesystemclaim.

## Goal round63 — detached scanner cancellation handoff

- importtask checks cancellation before creatingscanner and forwards itscancellation throughwithTaskCancellationHandler. Shutdownsnapshot taken before importtaskstarts cannot accidentallyspawnuncancelled scanner thenwaitforfullwalk. Existing immediateshutdownnative test covers queuepublication but runtime pending.
- Full pinnedLGPLsuite now48corepass+1ImageIOskip, scanner6,persistence15,Python31; includeslongfilenames/reservations/probecancel. Native source/tests syntaxonly.

## Goal round64 — local-only StateStore URL

- StateStore load/save/quarantine explicitly reject nonfileURLs before usingurl.path/filesystem. Injected remoteURL matchingexistinglocalpath cannot read/copy/chmod/overwrite it; dedicatedrealfile regression checks unchangedbytes anddirectorycontents.
- StrictSwift6portablepersistence16/16passes; defaultappuseslocalURLunchanged. Native filesystemverification pending.

## Goal round65 — local-only core history URL

- HistoryStore constructorrejectsnonfileURLs beforeload/save canusepath, extending localonlycontract toseparatecoreprimitive. ActualregressionHTTPSURLwithlocalpath preservesexistingbytes/directory.
- Threehistorytests passstrictSwift6. New49thcoretest targetedonly; complete48countretainedpendingrerun.

## Goal round66 — quarantine rejects nonregular state

- Quarantine now checksregularsource beforecopy/chmod; corruptdirectory no longer recursively copied, symlink no longercopiedthenpotentialtargetchmod. Regularcorrupt/oversizedstate remainsrecoverable withoutbytechanges.
- Actualdirectory/symlink tests verify no backups, targetbytes/644permissions unchanged; strictSwift6persistence17/17passes. Not malicioussameuserTOCTOUproof.

## Goal round67 — native batch continues after failure

- Expanded serialactualbatchtest with secondbatch missinginput→realFLAC job. Requires firstfailed/nooutput/diagnostic, nextcompleteduniqueoutput, zeroactivetasks, restoredqueue/history5/originalbytes. Usesmanagedawait; noflakytimepolling. Native14tests syntaxonlyhere.
- Full pinnedLGPLunifiedrun49corepasses+1ImageIOskip, scanner6,persistence17,Python31. Nativeexecution remainsmacOSgate.

## Goal round68 — network-disabled release configuration gate

- Bundleconfigurationverification now requiresdisable-network and rejectscontradictoryenable-network token aswellaslicenseexternalflags. Buildscript alreadydisablesnetwork; verifierenforces invariant rather thantrusting script.
- Python31/31passmissingnetwork/contradictoryflags cases; actualpinnedLGPL8.0.1buildconf accepted. Initialliteraleditbackslashmismatch correctedafterread, nohiddenretry. Nativebundlegateverificationstillpending.

## Goal round69 — ImageIO cancellation stage boundaries

- ImageConverter checks cancellation afterpreflight/thumbnail/render beforestartingnextcostlystage/privateworkspace, supplementing initial/final checks. DoesnotinterruptImageIOmidencode but avoidsadditionalworkaftercancel. AddedseventhnativeImageIOtestprecancel/missingsource/nofiles.
- NativeImageIOsource/testsyntaxparseonly; LinuxconditionalbranchesnotAPItypechecked. Twoportablecoreprecanceltests reallypass. No nativeImageIOexecutionclaim.

## Goal round70 — actual application exit uses shutdown

- Appdelegate previouslyterminateNow unlessconversion/importactive, bypassingnewcapabilitycancellation andidlefinalpersist. Nowallmodel-backedexitspathsterminateLater→cancelAndWait→reply; confirmationdialog onlyactiveconversion/import. Repeatedquitguardretained.
- Native source/testsyntaxparse andPython31/31pass. RequiresrealAppKitquit/capabilityprocess/idlehistorypersistence acceptance, no macOSruntimeclaim.

## Goal round71 — native platform load-command gate

- Bundleverifier now requiresLC_BUILD_VERSION platformmacOS (numeric1 orsymbolicmacos/MACOS), notonlyarchitecture/minOS. iOS/Catalystsamearm64minOS14 cannotpass mistakenasmacOS. LegacyLC_VERSION_MIN_MACOSX retained.
- Executedparserregressions acceptance/rejection andPython32/32pass. ActualotoolDarwinoutput notavailable; noproductionbundleverificationclaim.

## Goal round72 — each deployment command has minimumOS

- Platformgate now validates minimumfield for eachLC_BUILD_VERSION/LC_VERSION_MIN_MACOSX block; onevalidcommand no longer masks anothermissingminimum ornewerOS. SDKfield cannotstandin forminOS. Existingbundleaggregatemincheckretained.
- Newexecutedmulticommandparsercases andPython33/33pass. SyntheticMachOtext notactualnativeartifactverification.

## Goal round73 — one deployment parser

- Removedolderaggregate deploymentregex/check afternew stricterpercommandhelper; preservesgate/publicAPI whileavoidingtwodriftingimplementations. Testsrunbeforeandaftermechanicalrefactor.
- Python33/33before/after andpycompile/diffcheckpass. NativeMachOverificationstillpending.

## Goal round74 — real long Unicode source conversion

- Added actualpinnedLGPLenginefixture/conversion test with254UTF8bytesCyrillicsourcefilename→boundedFLACoutput; fullprobe/decode/publicationpipelinepasses, originalbytesunchanged/privateworkspacecleaned. Supplements earlierpublicationonlylongname test.
- Targeted50thcoretestpassSwift6; full49countretainedpendingrerun. macOSfilesystemnotexecutedhere.

## Goal round75 — both complete engine configurations rerun

- Unifieddevelopmentverificationpassedagain withDebian5.1.9GPLtestonlyengine(all18profiles) andpinnedsourcebuiltLGPL8.0.1(13supported,5explicitunavailable). Each50corepass+1nativeImageIOskip, scanner6,persistence17,Python33. StrictSwift6/nativeparse/shell/diffgatespass.
- Statusledgerupdatedcurrent50counts, keepingtestenginevsnativeproductionboundary. No bundledmacOSbuild, signing, distributions, orremoteexecutionclaim.

## Authorized native CI handoff — 2026-10-13

- User explicitly approved initial author Maya Moon <180734624+sorried@users.noreply.github.com>, separate-branch push and dual-architecture CI without tags/releases. Repository-local author configured; branch mediaforge/native-verification created. Scoped core/app/build commits created, preserving initial LICENSE. No fabricated retrospective commits.
- Completed round76 capability flags hardening: reject malformed six-character flag tokens; subprocess regression passes. Full pinned LGPL verification now51corepasses+1ImageIOskip, scanner6,persistence17,Python33. Native code remains syntax-only.
- gh auth status exited1: no GitHub authentication present. No push or Actions run attempted; native handoff requires user login. Authorization alone does not supply credentials.

## Goal round77 — review branch triggers native build

- Added exact authorized review branch to push filter; previously only main/tags triggered so separate branch push would not start build. Release remains v-tag-only, no tags authorized. Context7 GitHub Actions docs checked.
- Python34/34 including reviewbranch/tag-only wiring regression. GitHub authentication still absent; no push/remote CI executed.

## Goal round78 — retain native compiler/test diagnostics

- Native build capturesXcode/Swifttestcombinedoutput via tee underpipefail. Always-upload usesseparate native-diagnostics-* names, excludedfromreleaseMediaForge-*artifactpattern. Logs onlycompiler/tests, never signingcredentials.
- Python35/35, bashsyntax/diffpass; actualpipelineexit7 preserved(noincorrectsuccess). NativejobsnotexecuteduntilGitHublogin.

## Goal round79 — native handoff blocked on authentication

- Final committedsourceverification passes51core+1ImageIOskip, scanner6,persistence17,Python35; nativeparseonly. Reviewbranchready, no backgroundjobs.
- GitHublogin remainsabsent acrossrounds77–79 (ghauthstatus exit1). HostLinux/noXcode; authorizedremoteCI cannotstartwithoutcredentials. Stoppingautomaticroundsratherthanaddingunrelatedfixes. Resumeafteruserauthenticates. No push/tags/releasesperformed.

## First native CI execution — 2026-10-13

- Agent-local GitHub device login succeeded as sorried; authorized reviewbranch pushed c81d424. Actual run38437636593 on arm64/Intel Xcode26.6/17F113 passed architecture/toolchain/projectplutil/list gates but failed Python dependency-root test due macOS /var→/private/var canonicalization. No FFmpeg/appbuild or distributions yet. Release skipped.
- Canonicalized dependencycontainment root and added symlinkparent regression; LinuxPython36/36pass. Commit64ad817 pushed, run38437881806 started on botharchitectures. Actualresults awaited; no successclaim.

## Goal round83 — complete canonical test expectations

- Run38438133333 exposed remainingline26/28 expectations comparingresolvedactual to unresolvedexpected. Prior6647bba onlyfixedloaderassertion, incompletefix acknowledged. Nowboth executablepathassertions canonicalized; Python36/36, commitd656cc3pushed.
- BilingualREADME andrepositorydescription/topics published in47778f3; no release tags. NativeCI stillhasnotpassedprerequisites or produceddistributions.

## Native XCTest prerequisites — rounds84–87

- ActualCI Pythonpathchecks nowpass. macOSswiftc required platform XCTestframework+Swift overlay searchpaths (e2a25e2/9a41bc6). AppleXCTest doesnotprovideLinuxXCTMain/testCase; standaloneentryusesXCTestSuite withstrict6/17executioncounts (089eab7).
- Runtime thenrequiredXcodeSharedFrameworks forXCTestCore. Addedrpath andcapturedxcodeversionwithoutheadbrokenpipe (1db9bc3). Python36/36/localscanner6/persistence17 verified; nativeexecutionnotyetpassed. Run38440178194awaited.

## Native prerequisites and FFmpeg host SDK — rounds88–89

- Actualarm64run38440178194passed6import/17persistence tests; bothnativeprerequisitegates passed inrun38440536623. EngineconfigurefailedhostC11check. Diagnostics295af49revealedhostclangmissingSDK/ctype.h, notlackofC11support.
- Official8.0.1configure host-cc/host-cflags/host-ldflags inspected. bf7011epassesSDK/architectureflags tohostcompiler/linker; Python36pass, nativebuildrun38440847674awaited. NoFFmpeg/app/distribution successyet.

## Goal round93 — both native FFmpeg source builds succeed

- Run38440847674 builtLGPL8.0.1engineonarm64andx86_64. Bothappbuilds failedduplicate@main verificationfixture. Earlierfolderexception ineffective; exact Verification/ImportScannerChecks.swift membershipexceptionadded withupdatedstaticregression. Python36pass.
- Bothnativeappcompilelogs agree, actualfixedtargetbuild awaited. Noapplication/distributionsuccessyet.

## Next verification gates

1. Supply real Git author identity to allow required incremental local commits; do not invent identity.
2. Run native macOS CI on both architectures before creating artifacts or claiming native compilation.
3. Execute image/model tests, hardware encoder conversions and UI keyboard/VoiceOver checks on macOS; fix any Apple SDK/typecheck issues.
4. Validate real Sonoma runtime, dependencies, DMG contents and optional Developer ID/notarization.
5. Additional service-only image formats and abnormal-exit temporary-directory cleanup remain documented follow-ups; pending queue persistence is implemented but native relaunch still needs macOS verification.

Do not interpret deployment target as a Sonoma runtime test.
