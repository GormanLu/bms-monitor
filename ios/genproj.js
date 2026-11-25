// 生成 BMSMonitor.xcodeproj/project.pbxproj（Mac 上没有 xcodegen，工程文件用这个脚本生成）
// 三个目标：BMSMonitor（app）、BMSWidgetExtension（锁屏和灵动岛的实时活动、主屏幕小组件）、BMSWatch（Apple Watch app，嵌在 app 里）
// 用法：node genproj.js <ios 目录>
const fs = require('fs'), path = require('path');
const out = process.argv[2] || __dirname;
const TEAM = 'ZU27Q3S7UC', BUILD = 9, BUNDLE = 'com.gormanlu.bmsmonitor';

const appSrcs = ['BMSMonitorApp.swift', 'AppModel.swift', 'BLEManager.swift', 'FrameParser.swift', 'LogStore.swift', 'Uploader.swift',
  'RideTracker.swift', 'TripStore.swift', 'Notifier.swift', 'LiveActivityManager.swift', 'Components.swift', 'HomeView.swift',
  'RideView.swift', 'TripsView.swift', 'TrackViews.swift', 'NavManager.swift', 'NavViews.swift', 'Speaker.swift', 'Extras.swift', 'Badges.swift',
  'BatteryStats.swift', 'ExtraViews.swift', 'ContentView.swift', 'Features2.swift', 'Features3.swift', 'Views3.swift', 'PhoneLink.swift'];
const sharedSrcs = ['RideAttributes.swift', 'WidgetShare.swift'];   // app + 小组件
const watchShared = ['WatchState.swift'];                            // app + 手表
const widgetSrcs = ['BMSWidget.swift', 'HomeWidget.swift'];
const watchSrcs = ['BMSWatchApp.swift'];

let n = 0; const id = () => ('AB' + String(++n).padStart(22, '0'));
const ref = {}, bfApp = {}, bfWid = {}, bfWat = {};
for (const s of [...appSrcs, ...sharedSrcs, ...watchShared, ...widgetSrcs, ...watchSrcs]) ref[s] = id();
for (const s of [...appSrcs, ...sharedSrcs, ...watchShared]) bfApp[s] = id();
for (const s of [...widgetSrcs, ...sharedSrcs]) bfWid[s] = id();
for (const s of [...watchSrcs, ...watchShared]) bfWat[s] = id();
const appSrcAll = [...appSrcs, ...sharedSrcs, ...watchShared], widSrcAll = [...widgetSrcs, ...sharedSrcs], watSrcAll = [...watchSrcs, ...watchShared];

const assetsRef = id(), assetsBuild = id(), appPlist = id(), widPlist = id(), appEnt = id(), widEnt = id();
const appRef = id(), appexRef = id(), appexBuild = id(), watchRef = id(), watchBuild = id(), wAssetsRef = id(), wAssetsBuild = id();
const appSources = id(), appFrameworks = id(), appResources = id(), embedPhase = id(), watchEmbed = id();
const widSources = id(), widFrameworks = id(), widResources = id();
const watSources = id(), watFrameworks = id(), watResources = id();
const gRoot = id(), gApp = id(), gShared = id(), gWid = id(), gWat = id(), gProducts = id();
const tApp = id(), tWid = id(), tWat = id(), project = id(), proxy = id(), dep = id(), proxyW = id(), depW = id();
const cfgPD = id(), cfgPR = id(), cfgAD = id(), cfgAR = id(), cfgWD = id(), cfgWR = id(), cfgXD = id(), cfgXR = id();
const listP = id(), listA = id(), listW = id(), listX = id();

const list = (items, indent) => items.map(x => indent + x + ',').join('\n');
const fileRefLine = s => `		${ref[s]} /* ${s} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${s}; sourceTree = "<group>"; };`;
const buildLines = (srcs, bf) => srcs.map(s => `		${bf[s]} /* ${s} in Sources */ = {isa = PBXBuildFile; fileRef = ${ref[s]} /* ${s} */; };`).join('\n');
const emptyPhase = (pid, isa, name) => `		${pid} /* ${name} */ = {
			isa = ${isa};
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};`;
const cfgPair = (d, r, body) => [d, r].map((c, i) => `		${c} /* ${i ? 'Release' : 'Debug'} */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				${body}
			};
			name = ${i ? 'Release' : 'Debug'};
		};`).join('\n');
const cfgList = (l, d, r) => `		${l} = {
			isa = XCConfigurationList;
			buildConfigurations = (
				${d} /* Debug */,
				${r} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};`;

const common = `ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.2;
				SDKROOT = iphoneos;
				SWIFT_VERSION = 5.0;`;
const appCfg = `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = BMSMonitor/BMSMonitor.entitlements;
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
				CODE_SIGN_ENTITLEMENTS = BMSWidget/BMSWidget.entitlements;
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
const watCfg = `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = ${BUILD};
				DEVELOPMENT_TEAM = ${TEAM};
				ENABLE_PREVIEWS = NO;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = "电池监控";
				INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
				INFOPLIST_KEY_WKCompanionAppBundleIdentifier = ${BUNDLE};
				INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = NO;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE}.watchkitapp;
				PRODUCT_NAME = BMSWatch;
				SDKROOT = watchos;
				SKIP_INSTALL = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 10.0;`;

const t = `// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
${buildLines(appSrcAll, bfApp)}
${buildLines(widSrcAll, bfWid)}
${buildLines(watSrcAll, bfWat)}
		${assetsBuild} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ${assetsRef} /* Assets.xcassets */; };
		${wAssetsBuild} /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = ${wAssetsRef} /* Assets.xcassets */; };
		${appexBuild} /* BMSWidgetExtension.appex in Embed Foundation Extensions */ = {isa = PBXBuildFile; fileRef = ${appexRef} /* BMSWidgetExtension.appex */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
		${watchBuild} /* BMSWatch.app in Embed Watch Content */ = {isa = PBXBuildFile; fileRef = ${watchRef} /* BMSWatch.app */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		${proxy} /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = ${project} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = ${tWid};
			remoteInfo = BMSWidgetExtension;
		};
		${proxyW} /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = ${project} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = ${tWat};
			remoteInfo = BMSWatch;
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
		${watchEmbed} /* Embed Watch Content */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
			dstSubfolderSpec = 16;
			files = (
				${watchBuild} /* BMSWatch.app in Embed Watch Content */,
			);
			name = "Embed Watch Content";
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
${[...appSrcs, ...sharedSrcs, ...watchShared, ...widgetSrcs, ...watchSrcs].map(fileRefLine).join('\n')}
		${assetsRef} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		${wAssetsRef} /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		${appPlist} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		${widPlist} /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		${appEnt} /* BMSMonitor.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = BMSMonitor.entitlements; sourceTree = "<group>"; };
		${widEnt} /* BMSWidget.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = BMSWidget.entitlements; sourceTree = "<group>"; };
		${appRef} /* BMSMonitor.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = BMSMonitor.app; sourceTree = BUILT_PRODUCTS_DIR; };
		${appexRef} /* BMSWidgetExtension.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = BMSWidgetExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; };
		${watchRef} /* BMSWatch.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = BMSWatch.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
${emptyPhase(appFrameworks, 'PBXFrameworksBuildPhase', 'Frameworks')}
${emptyPhase(widFrameworks, 'PBXFrameworksBuildPhase', 'Frameworks')}
${emptyPhase(watFrameworks, 'PBXFrameworksBuildPhase', 'Frameworks')}
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		${gRoot} = {
			isa = PBXGroup;
			children = (
				${gApp} /* BMSMonitor */,
				${gShared} /* Shared */,
				${gWid} /* BMSWidget */,
				${gWat} /* BMSWatch */,
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
				${appEnt} /* BMSMonitor.entitlements */,
			);
			path = BMSMonitor;
			sourceTree = "<group>";
		};
		${gShared} /* Shared */ = {
			isa = PBXGroup;
			children = (
${list([...sharedSrcs, ...watchShared].map(s => `${ref[s]} /* ${s} */`), '				')}
			);
			path = Shared;
			sourceTree = "<group>";
		};
		${gWid} /* BMSWidget */ = {
			isa = PBXGroup;
			children = (
${list(widgetSrcs.map(s => `${ref[s]} /* ${s} */`), '				')}
				${widPlist} /* Info.plist */,
				${widEnt} /* BMSWidget.entitlements */,
			);
			path = BMSWidget;
			sourceTree = "<group>";
		};
		${gWat} /* BMSWatch */ = {
			isa = PBXGroup;
			children = (
${list(watchSrcs.map(s => `${ref[s]} /* ${s} */`), '				')}
				${wAssetsRef} /* Assets.xcassets */,
			);
			path = BMSWatch;
			sourceTree = "<group>";
		};
		${gProducts} /* Products */ = {
			isa = PBXGroup;
			children = (
				${appRef} /* BMSMonitor.app */,
				${appexRef} /* BMSWidgetExtension.appex */,
				${watchRef} /* BMSWatch.app */,
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
				${watchEmbed} /* Embed Watch Content */,
			);
			buildRules = (
			);
			dependencies = (
				${dep} /* PBXTargetDependency */,
				${depW} /* PBXTargetDependency */,
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
		${tWat} /* BMSWatch */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = ${listX};
			buildPhases = (
				${watSources} /* Sources */,
				${watFrameworks} /* Frameworks */,
				${watResources} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = BMSWatch;
			productName = BMSWatch;
			productReference = ${watchRef} /* BMSWatch.app */;
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
					${tApp} = {
						CreatedOnToolsVersion = 15.0;
					};
					${tWid} = {
						CreatedOnToolsVersion = 15.0;
					};
					${tWat} = {
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
				${tWat} /* BMSWatch */,
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
${emptyPhase(widResources, 'PBXResourcesBuildPhase', 'Resources')}
		${watResources} /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				${wAssetsBuild} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		${appSources} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
${list(appSrcAll.map(s => `${bfApp[s]} /* ${s} in Sources */`), '				')}
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${widSources} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
${list(widSrcAll.map(s => `${bfWid[s]} /* ${s} in Sources */`), '				')}
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		${watSources} /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
${list(watSrcAll.map(s => `${bfWat[s]} /* ${s} in Sources */`), '				')}
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
		${depW} /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = ${tWat} /* BMSWatch */;
			targetProxy = ${proxyW} /* PBXContainerItemProxy */;
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
${cfgPair(cfgAD, cfgAR, appCfg)}
${cfgPair(cfgWD, cfgWR, widCfg)}
${cfgPair(cfgXD, cfgXR, watCfg)}
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
${cfgList(listP, cfgPD, cfgPR)}
${cfgList(listA, cfgAD, cfgAR)}
${cfgList(listW, cfgWD, cfgWR)}
${cfgList(listX, cfgXD, cfgXR)}
/* End XCConfigurationList section */
	};
	rootObject = ${project} /* Project object */;
}
`;
fs.mkdirSync(path.join(out, 'BMSMonitor.xcodeproj'), { recursive: true });
fs.writeFileSync(path.join(out, 'BMSMonitor.xcodeproj', 'project.pbxproj'), t);
console.log('written');
