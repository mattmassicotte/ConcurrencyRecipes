// swift-tools-version: 5.10

import PackageDescription

let settings: [SwiftSetting] = [
	.enableExperimentalFeature("StrictConcurrency")
]

let package = Package(
	name: "ConcurrencyRecipes",
	products: [
//		.library(
//			name: "ConcurrencyRecipes",
//			targets: ["ConcurrencyRecipes"]
//		),
	],
	targets: [
		.target(name: "PreconcurrencyLib"),
//		.target(
//			name: "ConcurrencyRecipes",
//			swiftSettings: settings
//		),
		.testTarget(
			name: "ConcurrencyRecipesTests",
			dependencies: ["PreconcurrencyLib"],
			swiftSettings: settings
		),
	]
)
