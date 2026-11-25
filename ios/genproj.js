// 生成 BMSMonitor.xcodeproj/project.pbxproj（Mac 上没有 xcodegen，工程文件用这个脚本生成）
// 用法：node genproj.js <ios 目录>
const fs = require('fs'), path = require('path');
const out = process.argv[2] || __dirname;
const srcs = ['BMSMonitorApp.swift', 'AppModel.swift', 'BLEManager.swift', 'FrameParser.swift', 'LogStore.swift', 'Uploader.swift', 'RideTracker.swift', 'ContentView.swift'];
let n = 0; const id = () => ('AB' + String(++n).padStart(22, '0'));
const fileRef = {}, buildFile = {};
for (const s of srcs) { fileRef[s] = id(); buildFile[s] = id(); }
const assetsRef = id(), assetsBuild = id();
const plistRef = id(), appRef = id(), frameworks = id(), sources = id(), resources = id();
const gRoot = id(), gMain = id(), gProducts = id(), target = id(), project = id();
const cfgProjD = id(), cfgProjR = id(), cfgTgtD = id(), cfgTgtR = id(), listProj = id(), listTgt = id();
const common = `ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;`;
const tgt = `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 2;
				DEVELOPMENT_TEAM = ZU27Q3S7UC;
				ENABLE_PREVIEWS = NO;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = BMSMonitor/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.gormanlu.bmsmonitor;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;`;
const t = `// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
${srcs.map(s => `		${buildFile[s]} /* ${s} in Sources */ = {isa = PBXBuildFile; fileRef = ${fileRef[s]} /* ${s} */; };`).join('\n')}
		${assetsBuild} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ${assetsRef} /* Assets.xcassets */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
${srcs.map(s => `		${fileRef[s]} /* ${s} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${s}; sourceTree = "<group>"; };`).join('\n')}
		${assetsRef} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		${plistRef} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		${appRef} /* BMSMonitor.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = BMSMonitor.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		${frameworks} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		${gRoot} = {
			isa = PBXGroup;
			children = (
				${gMain} /* BMSMonitor */,
				${gProducts} /* Products */,
			);
			sourceTree = "<group>";
		};
		${gMain} /* BMSMonitor */ = {
			isa = PBXGroup;
			children = (
${srcs.map(s => `				${fileRef[s]} /* ${s} */,`).join('\n')}
				${assetsRef} /* Assets.xcassets */,
				${plistRef} /* Info.plist */,
			);
			path = BMSMonitor;
			sourceTree = "<group>";
		};
		${gProducts} /* Products */ = {
			isa = PBXGroup;
			children = (
				${appRef} /* BMSMonitor.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		${target} /* BMSMonitor */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${listTgt} /* Build configuration list for PBXNativeTarget "BMSMonitor" */;
			buildPhases = (
				${sources} /* Sources */,
				${frameworks} /* Frameworks */,
				${resources} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = BMSMonitor;
			productName = BMSMonitor;
			productReference = ${appRef} /* BMSMonitor.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		${project} /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					${target} = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = ${listProj} /* Build configuration list for PBXProject "BMSMonitor" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = "zh-Hans";
			hasScannedForEncodings = 0;
			knownRegions = (
				"zh-Hans",
				en,
				Base,
			);
			mainGroup = ${gRoot};
			productRefGroup = ${gProducts} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				${target} /* BMSMonitor */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		${resources} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${assetsBuild} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		${sources} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
${srcs.map(s => `				${buildFile[s]} /* ${s} in Sources */,`).join('\n')}
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		${cfgProjD} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				${common}
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		${cfgProjR} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				${common}
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		${cfgTgtD} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				${tgt}
			};
			name = Debug;
		};
		${cfgTgtR} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				${tgt}
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		${listProj} /* Build configuration list for PBXProject "BMSMonitor" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${cfgProjD} /* Debug */,
				${cfgProjR} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		${listTgt} /* Build configuration list for PBXNativeTarget "BMSMonitor" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${cfgTgtD} /* Debug */,
				${cfgTgtR} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = ${project} /* Project object */;
}
`;
fs.mkdirSync(path.join(out, 'BMSMonitor.xcodeproj'), { recursive: true });
fs.writeFileSync(path.join(out, 'BMSMonitor.xcodeproj', 'project.pbxproj'), t);
console.log('written');
