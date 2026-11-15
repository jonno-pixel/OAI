#!/usr/bin/env python3
"""Generate this app's standalone Xcode project; no existing project is copied."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
def ident(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()
def q(value):
    return json.dumps(value)
objects = []
def obj(key, body):
    objects.append(f'\t{ident(key)} = {{ {body} }};')
def refs(keys):
    return '(' + ','.join(ident(key) for key in keys) + ')'

sources = sorted(p.name for p in (root / 'Sources').glob('*.swift'))
for name in sources:
    obj('source:' + name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(name)}; sourceTree = "<group>";')
    obj('compile:' + name, f'isa = PBXBuildFile; fileRef = {ident("source:" + name)};')
resources = ['Assets.xcassets', 'PrivacyInfo.xcprivacy', 'LLAMA-LICENSE.txt']
for name in resources:
    kind = 'folder.assetcatalog' if name.endswith('xcassets') else 'text'
    obj('resource:' + name, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(name)}; sourceTree = "<group>";')
    obj('bundle:' + name, f'isa = PBXBuildFile; fileRef = {ident("resource:" + name)};')
obj('framework', 'isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; path = Frameworks/llama.xcframework; sourceTree = "<group>";')
obj('link', f'isa = PBXBuildFile; fileRef = {ident("framework")};')
obj('embed', f'isa = PBXBuildFile; fileRef = {ident("framework")}; settings = {{ ATTRIBUTES = (CodeSignOnCopy,RemoveHeadersOnCopy); }};')
obj('info', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = JJSVrij.app; sourceTree = BUILT_PRODUCTS_DIR; includeInIndex = 0;')
obj('sources', f'isa = PBXGroup; path = Sources; children = {refs(["source:"+name for name in sources])}; sourceTree = "<group>";')
obj('products', f'isa = PBXGroup; name = Products; children = {refs(["product"])}; sourceTree = "<group>";')
obj('main', f'isa = PBXGroup; children = {refs(["sources"]+["resource:"+name for name in resources]+["framework","info","products"])}; sourceTree = "<group>";')
obj('compile', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {refs(["compile:"+name for name in sources])}; runOnlyForDeploymentPostprocessing = 0;')
obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {refs(["bundle:"+name for name in resources])}; runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {refs(["link"])}; runOnlyForDeploymentPostprocessing = 0;')
obj('embedphase', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 10; name = "Embed Native Library"; files = {refs(["embed"])}; runOnlyForDeploymentPostprocessing = 0;')
for mode in ['Debug', 'Release']:
    obj('project:' + mode, 'isa = XCBuildConfiguration; name = ' + mode + '; buildSettings = { SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; CLANG_ENABLE_MODULES = YES; };')
    settings = {
        'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'CODE_SIGN_STYLE': 'Automatic',
        'CODE_SIGNING_ALLOWED': 'YES', 'CURRENT_PROJECT_VERSION': '5',
        'MARKETING_VERSION': '2.0.2', 'GENERATE_INFOPLIST_FILE': 'NO',
        'INFOPLIST_FILE': 'Info.plist', 'PRODUCT_BUNDLE_IDENTIFIER': 'nl.jjs.vrij',
        'PRODUCT_NAME': 'JJSVrij', 'SWIFT_VERSION': '5.0',
        'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'SUPPORTED_PLATFORMS': 'iphoneos',
        'TARGETED_DEVICE_FAMILY': '1,2', 'SUPPORTS_MACCATALYST': 'NO',
        'ENABLE_USER_SCRIPT_SANDBOXING': 'YES', 'CLANG_ENABLE_MODULES': 'YES',
        'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode == 'Debug' else '-O',
        'DEBUG_INFORMATION_FORMAT': 'dwarf' if mode == 'Debug' else 'dwarf-with-dsym',
    }
    body = ' '.join(key + ' = ' + q(value) + ';' for key, value in settings.items())
    body += ' LD_RUNPATH_SEARCH_PATHS = ("$(inherited)","@executable_path/Frameworks");'
    body += ' OTHER_LDFLAGS = ("$(inherited)","-lc++","-framework",Accelerate,"-framework",Metal);'
    obj('target:' + mode, f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {body} }};')
for level in ['project', 'target']:
    obj(level + ':configs', f'isa = XCConfigurationList; buildConfigurations = {refs([level+":Debug",level+":Release"])}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target', f'isa = PBXNativeTarget; name = JJSVrij; productName = JJSVrij; productType = "com.apple.product-type.application"; productReference = {ident("product")}; buildConfigurationList = {ident("target:configs")}; buildPhases = {refs(["compile","frameworks","resources","embedphase"])}; buildRules = (); dependencies = ();')
obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; BuildIndependentTargetsInParallel = YES; }}; buildConfigurationList = {ident("project:configs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = nl; knownRegions = (nl,en,Base); mainGroup = {ident("main")}; productRefGroup = {ident("products")}; projectDirPath = ""; projectRoot = ""; targets = {refs(["target"])};')
project = root / 'JJSVrij.xcodeproj'
project.mkdir(exist_ok=True)
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\narchiveVersion = 1; classes = {}; objectVersion = 56;\nobjects = {\n' + '\n'.join(objects) + '\n};\nrootObject = ' + ident('project') + ';\n}\n')
scheme = project / 'xcshareddata/xcschemes/JJSVrij.xcscheme'
scheme.parent.mkdir(parents=True, exist_ok=True)
scheme.write_text('''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="''' + ident('target') + '''" BuildableName="JJSVrij.app" BlueprintName="JJSVrij" ReferencedContainer="container:JJSVrij.xcodeproj"/>
</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES">
<BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="''' + ident('target') + '''" BuildableName="JJSVrij.app" BlueprintName="JJSVrij" ReferencedContainer="container:JJSVrij.xcodeproj"/></BuildableProductRunnable>
</LaunchAction>
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(f'Generated standalone project for {len(sources)} new Swift source files')
