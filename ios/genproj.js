// 生成 BMSMonitor.xcodeproj/project.pbxproj（Mac 上没有 xcodegen，工程文件用这个脚本生成）
// 两个目标：BMSMonitor（app）和 BMSWidgetExtension（锁屏和灵动岛的实时活动）
// 用法：node genproj.js <ios 目录>
const fs = require('fs'), path = require('path');
const out = process.argv[2] || __dirname;
const TEAM = 'ZU27Q3S7UC', BUILD = 7, BUNDLE = 'com.gormanlu.bmsmonitor';

const appSrcs = ['BMSMonitorApp.swift', 'AppModel.swift', 'BLEManager.swift', 'FrameParser.swift', 'LogStore.swift', 'Uploader.swift',
  'RideTracker.swift', 'TripStore.swift', 'Notifier.swift', 'LiveActivityManager.swift', 'Components.swift', 'HomeView.swift',
  'RideView.swift', 'TripsView.swift', 'TrackViews.swift', 'NavManager.swift', 'NavViews.swift', 'Speaker.swift', 'Extras.swift', 'Badges.swift', 'BatteryStats.swift', 'ExtraViews.swift', 'ContentView.swift'];
const sharedSrcs = ['RideAttributes.swift'];
const widgetSrcs = ['BMSWidget.swift'];

let n = 0; const id = () => ('AB' + String(++n).padStart(22, '0'));
const ref = {}, bfApp = {}, bfWid = {};
for (const s of [...appSrcs, ...sharedSrcs, ...widgetSrcs]) ref[s] = id();
for (const s of [...appSrcs, ...sharedSrcs]) bfApp[s] = id();
for (const s of [...widgetSrcs, ...sharedSrcs]) bfWid[s] = id();
const assetsRef = id(), assetsBuild = id(), appPlist = id(), widPlist = id(), appRef = id(), appexRef = id(), appexBuild = id();
const appSources = id(), appFrameworks = id(), appResources = id(), embedPhase = id();
const widSources = id(), widFrameworks = id(), widResources = id();
const gRoot = id(), gApp = id(), gShared = id(), gWid = id(), gProducts = id();
const tApp = id(), tWid = id(), project = id(), proxy = id(), dep = id();
const cfgPD = id(), cfgPR = id(), cfgAD = id(), cfgAR = id(), cfgWD = id(), cfgWR = id(), listP = id(), listA = id(), listW = id();

const list = (items, indent) => items.map(x => indent + x + ',').join('\n');
const fileRefLine = (s, dir) => `		${ref[s]} /* ${s} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${s}; sourceTree = "<group>"; };`;

const common = `ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.2;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;`;
const appCfg = `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = ${BUILD};
				DEVELOPMENT_TEAM = ${TEAM};
				ENABLE_PREVIEWS = NO;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = BMSMonitor/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE};
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;`;
const widCfg = `APPLICATION_EXTENSION_API_ONLY = YES;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = ${BUILD};
				DEVELOPMENT_TEAM = ${TEAM};
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = BMSWidget/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE}.widget;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
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
${[...appSrcs, ...sharedSrcs].map(s => `		${bfApp[s]} /* ${s} in Sources */ = {isa = PBXBuildFile; fileRef = ${ref[s]} /* ${s} */; };`).join('\n')}
${[...widgetSrcs, ...sharedSrcs].map(s => `		${bfWid[s]} /* ${s} in Sources */ = {isa = PBXBuildFile; fileRef = ${ref[s]} /* ${s} */; };`).join('\n')}
		${assetsBuild} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ${assetsRef} /* Assets.xcassets */; };
		${appexBuild} /* BMSWidgetExtension.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = ${appexRef} /* BMSWidgetExtension.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		${proxy} /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = ${project} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = ${tWid};
			remoteInfo = BMSWidgetExtension;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
		${embedPhase} /* Embed Foundation Extensions */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				${appexBuild} /* BMSWidgetExtension.appex in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
${appSrcs.map(s => fileRefLine(s)).join('\n')}
${sharedSrcs.map(s => fileRefLine(s)).join('\n')}
${widgetSrcs.map(s => fileRefLine(s)).join('\n')}
		${assetsRef} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		${appPlist} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		${widPlist} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		${appRef} /* BMSMonitor.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = BMSMonitor.app; sourceTree = BUILT_PRODUCTS_DIR; };
		${appexRef} /* BMSWidgetExtension.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = BMSWidgetExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		${appFrameworks} /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${widFrameworks} /* Frameworks */ = {
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
				${gApp} /* BMSMonitor */,
				${gShared} /* Shared */,
				${gWid} /* BMSWidget */,
				${gProducts} /* Products */,
			);
			sourceTree = "<group>";
		};
		${gApp} /* BMSMonitor */ = {
			isa = PBXGroup;
			children = (
${list(appSrcs.map(s => `${ref[s]} /* ${s} */`), '				')}
				${assetsRef} /* Assets.xcassets */,
				${appPlist} /* Info.plist */,
			);
			path = BMSMonitor;
			sourceTree = "<group>";
		};
		${gShared} /* Shared */ = {
			isa = PBXGroup;
			children = (
${list(sharedSrcs.map(s => `${ref[s]} /* ${s} */`), '				')}
			);
			path = Shared;
			sourceTree = "<group>";
		};
		${gWid} /* BMSWidget */ = {
			isa = PBXGroup;
			children = (
${list(widgetSrcs.map(s => `${ref[s]} /* ${s} */`), '				')}
				${widPlist} /* Info.plist */,
			);
			path = BMSWidget;
			sourceTree = "<group>";
		};
		${gProducts} /* Products */ = {
			isa = PBXGroup;
			children = (
				${appRef} /* BMSMonitor.app */,
				${appexRef} /* BMSWidgetExtension.appex */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		${tApp} /* BMSMonitor */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${listA};
			buildPhases = (
				${appSources} /* Sources */,
				${appFrameworks} /* Frameworks */,
				${appResources} /* Resources */,
				${embedPhase} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				${dep} /* PBXTargetDependency */,
			);
			name = BMSMonitor;
			productName = BMSMonitor;
			productReference = ${appRef} /* BMSMonitor.app */;
			productType = "com.apple.product-type.application";
		};
		${tWid} /* BMSWidgetExtension */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${listW};
			buildPhases = (
				${widSources} /* Sources */,
				${widFrameworks} /* Frameworks */,
				${widResources} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = BMSWidgetExtension;
			productName = BMSWidgetExtension;
			productReference = ${appexRef} /* BMSWidgetExtension.appex */;
			productType = "com.apple.product-type.app-extension";
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
					${tApp} = {
						CreatedOnToolsVersion = 15.0;
					};
					${tWid} = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = ${listP};
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
				${tApp} /* BMSMonitor */,
				${tWid} /* BMSWidgetExtension */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		${appResources} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${assetsBuild} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${widResources} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		${appSources} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
${list([...appSrcs, ...sharedSrcs].map(s => `${bfApp[s]} /* ${s} in Sources */`), '				')}
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${widSources} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
${list([...widgetSrcs, ...sharedSrcs].map(s => `${bfWid[s]} /* ${s} in Sources */`), '				')}
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		${dep} /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = ${tWid} /* BMSWidgetExtension */;
			targetProxy = ${proxy} /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		${cfgPD} /* Debug */ = {
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
		${cfgPR} /* Release */ = {
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
		${cfgAD} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				${appCfg}
			};
			name = Debug;
		};
		${cfgAR} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				${appCfg}
			};
			name = Release;
		};
		${cfgWD} /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				${widCfg}
			};
			name = Debug;
		};
		${cfgWR} /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				${widCfg}
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		${listP} = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${cfgPD} /* Debug */,
				${cfgPR} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		${listA} = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${cfgAD} /* Debug */,
				${cfgAR} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		${listW} = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${cfgWD} /* Debug */,
				${cfgWR} /* Release */,
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
