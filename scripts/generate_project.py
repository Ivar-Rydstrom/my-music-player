#!/usr/bin/env python3
"""Generate the dependency-free Xcode project from Sources/."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent
project = root / "StillPlayer.xcodeproj"
project.mkdir(exist_ok=True)

def uid(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

objects = []
def obj(name, contents):
    objects.append(f"\t\t{uid(name)} = {{ {contents} }};")
    return uid(name)

files, builds = [], []
for path in sorted((root / "Sources").rglob("*.swift")):
    relative = str(path.relative_to(root))
    file = obj(relative, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{relative}"; sourceTree = SOURCE_ROOT;')
    files.append(file)
    builds.append(obj(relative + ":build", f"isa = PBXBuildFile; fileRef = {file};"))

product = obj("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = StillPlayer.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj("products", f'isa = PBXGroup; children = ({product},); name = Products; sourceTree = "<group>";')
group = obj("main", f'isa = PBXGroup; children = ({",".join(files + [uid("signing"), products])},); sourceTree = "<group>";')
sources = obj("sources", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks = obj("frameworks", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
resources = obj("resources", 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
signing = obj("signing", 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/Signing.xcconfig; sourceTree = SOURCE_ROOT;')

def configs(prefix, settings, base=None):
    ids = []
    for name in ("Debug", "Release"):
        extra = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if name == "Debug" else 'SWIFT_OPTIMIZATION_LEVEL = "-O";'
        base_setting = f'baseConfigurationReference = {base};' if base else ''
        ids.append(obj(prefix + name, f'isa = XCBuildConfiguration; {base_setting} buildSettings = {{ {settings} {extra} }}; name = {name};'))
    return obj(prefix + "list", f'isa = XCConfigurationList; buildConfigurations = ({",".join(ids)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

project_configs = configs("project", 'MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES;')
target_configs = configs("target", '''PRODUCT_NAME = StillPlayer;
    INFOPLIST_FILE = Config/Info.plist;
    CODE_SIGN_ENTITLEMENTS = Config/StillPlayer.entitlements;
    ENABLE_HARDENED_RUNTIME = YES;
    SWIFT_EMIT_LOC_STRINGS = YES;
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
''', base=signing)
target = obj("target", f'isa = PBXNativeTarget; buildConfigurationList = {target_configs}; buildPhases = ({sources},{frameworks},{resources},); buildRules = (); dependencies = (); name = StillPlayer; productName = StillPlayer; productReference = {product}; productType = "com.apple.product-type.application";')
proj = obj("project", f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2610; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 26.1; }}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target},);')
(project / "project.pbxproj").write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + f'\n\t}};\n\trootObject = {proj};\n}}\n')
scheme_dir = project / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="StillPlayer.app" BlueprintName="StillPlayer" ReferencedContainer="container:StillPlayer.xcodeproj"/>'
(scheme_dir / "StillPlayer.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2610" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated StillPlayer.xcodeproj")
