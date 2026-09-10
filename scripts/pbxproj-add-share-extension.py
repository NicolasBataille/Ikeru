#!/usr/bin/env python3
"""Add the `IkeruShare` share-extension target to Ikeru.xcodeproj.

Hand-written rather than done in Xcode because the project file is the single
place two people (and every CI run) have to agree on, and an Xcode-authored
target arrives with dozens of unrelated reformattings that bury the change.

Everything here mirrors the existing `IkeruWidget` target — same product type,
same embed phase, same runpaths, same package dependency on IkeruCore — because
a share extension and a widget extension are the same kind of thing to the build
system, and copying a working shape beats inventing one.

Idempotent: run it twice and the second run does nothing.

Usage:
    python3 scripts/pbxproj-add-share-extension.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

PBXPROJ = Path(__file__).resolve().parent.parent / "Ikeru.xcodeproj" / "project.pbxproj"

# Identifiants figés, choisis hors de l'espace que Xcode génère (il tire des
# valeurs pseudo-aléatoires), pour que ce fichier reste relisible.
TARGET      = "5A17E0000000000000000001"
CONFLIST    = "5A17E0000000000000000002"
DEBUG       = "5A17E0000000000000000003"
RELEASE     = "5A17E0000000000000000004"
PRODUCT     = "5A17E0000000000000000005"
GROUP       = "5A17E0000000000000000006"
SOURCES     = "5A17E0000000000000000007"
FRAMEWORKS  = "5A17E0000000000000000008"
RESOURCES   = "5A17E0000000000000000009"
SWIFT_REF   = "5A17E000000000000000000A"
SWIFT_BUILD = "5A17E000000000000000000B"
PLIST_REF   = "5A17E000000000000000000C"
ENT_REF     = "5A17E000000000000000000D"
COREDEP     = "5A17E000000000000000000E"
CORE_BUILD  = "5A17E000000000000000000F"
EMBED_BUILD = "5A17E0000000000000000010"
TARGETDEP   = "5A17E0000000000000000011"
PROXY       = "5A17E0000000000000000012"

# Cibles et phases existantes servant d'ancrage.
APP_TARGET   = "EDDB8F3812DC1BC18F32017C"   # Ikeru
EMBED_PHASE  = "144B808990A1D5825BB8E28C"   # Embed Foundation Extensions
PRODUCTS     = "70A9DC9F6ECBB150C593E25D"
MAIN_GROUP   = "EF88C2B2433715E2D2E8D0DA"
PROJECT_OBJ  = "44FF3435A5B11DC2E0D31918"

# Réglages communs aux deux configurations, recopiés de IkeruWidget.
SETTINGS = """				CODE_SIGN_ENTITLEMENTS = IkeruShare/IkeruShare.entitlements;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = IkeruShare/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.ikeru.app.share;
				SDKROOT = iphoneos;
				SKIP_INSTALL = YES;
				SWIFT_VERSION = 6.0;
				TARGETED_DEVICE_FAMILY = 1;
"""


def insert_before(text: str, marker: str, block: str) -> str:
    if marker not in text:
        raise SystemExit(f"ancre introuvable : {marker}")
    return text.replace(marker, block + marker, 1)


def add_to_list(text: str, anchor: str, entry: str) -> str:
    match = re.search(anchor, text)
    if not match:
        raise SystemExit(f"liste introuvable : {anchor}")
    return text[:match.end()] + entry + text[match.end():]


def main() -> int:
    text = PBXPROJ.read_text(encoding="utf-8")
    if TARGET in text:
        print("déjà présent — rien à faire")
        return 0

    text = insert_before(text, "/* End PBXBuildFile section */", "".join([
        f"\t\t{SWIFT_BUILD} /* ShareViewController.swift in Sources */ = {{isa = PBXBuildFile; "
        f"fileRef = {SWIFT_REF} /* ShareViewController.swift */; }};\n",
        f"\t\t{CORE_BUILD} /* IkeruCore in Frameworks */ = {{isa = PBXBuildFile; "
        f"productRef = {COREDEP} /* IkeruCore */; }};\n",
        f"\t\t{EMBED_BUILD} /* IkeruShare.appex in Embed Foundation Extensions */ = "
        f"{{isa = PBXBuildFile; fileRef = {PRODUCT} /* IkeruShare.appex */; "
        f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n",
    ]))

    text = insert_before(text, "/* End PBXFileReference section */", "".join([
        f'\t\t{PRODUCT} /* IkeruShare.appex */ = {{isa = PBXFileReference; includeInIndex = 0; '
        f'lastKnownFileType = "wrapper.app-extension"; path = IkeruShare.appex; '
        f'sourceTree = BUILT_PRODUCTS_DIR; }};\n',
        f'\t\t{SWIFT_REF} /* ShareViewController.swift */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; path = ShareViewController.swift; '
        f'sourceTree = "<group>"; }};\n',
        f'\t\t{PLIST_REF} /* Info.plist */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};\n',
        f'\t\t{ENT_REF} /* IkeruShare.entitlements */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = text.plist.entitlements; path = IkeruShare.entitlements; '
        f'sourceTree = "<group>"; }};\n',
    ]))

    text = insert_before(text, "/* End PBXGroup section */",
        f"\t\t{GROUP} /* IkeruShare */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t\t{SWIFT_REF} /* ShareViewController.swift */,\n"
        f"\t\t\t\t{PLIST_REF} /* Info.plist */,\n"
        f"\t\t\t\t{ENT_REF} /* IkeruShare.entitlements */,\n"
        f"\t\t\t);\n"
        f"\t\t\tpath = IkeruShare;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};\n")

    text = insert_before(text, "/* End PBXNativeTarget section */",
        f"\t\t{TARGET} /* IkeruShare */ = {{\n"
        f"\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {CONFLIST} /* Build configuration list for "
        f"PBXNativeTarget \"IkeruShare\" */;\n"
        f"\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{SOURCES} /* Sources */,\n"
        f"\t\t\t\t{FRAMEWORKS} /* Frameworks */,\n"
        f"\t\t\t\t{RESOURCES} /* Resources */,\n"
        f"\t\t\t);\n"
        f"\t\t\tbuildRules = (\n\t\t\t);\n"
        f"\t\t\tdependencies = (\n\t\t\t);\n"
        f"\t\t\tname = IkeruShare;\n"
        f"\t\t\tpackageProductDependencies = (\n"
        f"\t\t\t\t{COREDEP} /* IkeruCore */,\n"
        f"\t\t\t);\n"
        f"\t\t\tproductName = IkeruShare;\n"
        f"\t\t\tproductReference = {PRODUCT} /* IkeruShare.appex */;\n"
        f"\t\t\tproductType = \"com.apple.product-type.app-extension\";\n"
        f"\t\t}};\n")

    text = insert_before(text, "/* End PBXSourcesBuildPhase section */",
        f"\t\t{SOURCES} /* Sources */ = {{\n"
        f"\t\t\tisa = PBXSourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{SWIFT_BUILD} /* ShareViewController.swift in Sources */,\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n")

    text = insert_before(text, "/* End PBXFrameworksBuildPhase section */",
        f"\t\t{FRAMEWORKS} /* Frameworks */ = {{\n"
        f"\t\t\tisa = PBXFrameworksBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{CORE_BUILD} /* IkeruCore in Frameworks */,\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n")

    text = insert_before(text, "/* End PBXResourcesBuildPhase section */",
        f"\t\t{RESOURCES} /* Resources */ = {{\n"
        f"\t\t\tisa = PBXResourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n")

    text = insert_before(text, "/* End XCBuildConfiguration section */", "".join([
        f"\t\t{DEBUG} /* Debug */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n{SETTINGS}\t\t\t}};\n\t\t\tname = Debug;\n\t\t}};\n",
        f"\t\t{RELEASE} /* Release */ = {{\n\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n{SETTINGS}\t\t\t}};\n\t\t\tname = Release;\n\t\t}};\n",
    ]))

    text = insert_before(text, "/* End XCConfigurationList section */",
        f"\t\t{CONFLIST} /* Build configuration list for PBXNativeTarget \"IkeruShare\" */ = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{DEBUG} /* Debug */,\n"
        f"\t\t\t\t{RELEASE} /* Release */,\n"
        f"\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Debug;\n"
        f"\t\t}};\n")

    text = insert_before(text, "/* End XCSwiftPackageProductDependency section */",
        f"\t\t{COREDEP} /* IkeruCore */ = {{\n"
        f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f"\t\t\tproductName = IkeruCore;\n"
        f"\t\t}};\n")

    text = insert_before(text, "/* End PBXContainerItemProxy section */",
        f"\t\t{PROXY} /* PBXContainerItemProxy */ = {{\n"
        f"\t\t\tisa = PBXContainerItemProxy;\n"
        f"\t\t\tcontainerPortal = {PROJECT_OBJ} /* Project object */;\n"
        f"\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {TARGET};\n"
        f"\t\t\tremoteInfo = IkeruShare;\n"
        f"\t\t}};\n")

    text = insert_before(text, "/* End PBXTargetDependency section */",
        f"\t\t{TARGETDEP} /* PBXTargetDependency */ = {{\n"
        f"\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\ttarget = {TARGET} /* IkeruShare */;\n"
        f"\t\t\ttargetProxy = {PROXY} /* PBXContainerItemProxy */;\n"
        f"\t\t}};\n")

    # Rattachements aux listes existantes.
    text = add_to_list(text, rf"\t\t{MAIN_GROUP} (?:/\* .+? \*/ )?= \{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n",
                       f"\t\t\t\t{GROUP} /* IkeruShare */,\n")
    text = add_to_list(text, rf"\t\t{PRODUCTS} /\* Products \*/ = \{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n",
                       f"\t\t\t\t{PRODUCT} /* IkeruShare.appex */,\n")
    text = add_to_list(text, rf"\t\t{EMBED_PHASE} /\* Embed Foundation Extensions \*/ = \{{\n(?:.*\n)*?\t\t\tfiles = \(\n",
                       f"\t\t\t\t{EMBED_BUILD} /* IkeruShare.appex in Embed Foundation Extensions */,\n")
    text = add_to_list(text, rf"\t\t{APP_TARGET} /\* Ikeru \*/ = \{{\n(?:.*\n)*?\t\t\tdependencies = \(\n",
                       f"\t\t\t\t{TARGETDEP} /* PBXTargetDependency */,\n")
    text = add_to_list(text, r"\t\t\ttargets = \(\n",
                       f"\t\t\t\t{TARGET} /* IkeruShare */,\n")

    PBXPROJ.write_text(text, encoding="utf-8")
    print("cible IkeruShare ajoutée")
    return 0


if __name__ == "__main__":
    sys.exit(main())
