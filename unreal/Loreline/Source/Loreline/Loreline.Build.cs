using UnrealBuildTool;
using System.IO;

public class Loreline : ModuleRules
{
	public Loreline(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[] {
			"Core",
			"CoreUObject",
			"Engine"
		});

		string ThirdPartyPath = Path.Combine(ModuleDirectory, "..", "ThirdParty", "Loreline");
		PublicIncludePaths.Add(Path.Combine(ThirdPartyPath, "Include"));

		if (Target.Platform == UnrealTargetPlatform.Win64)
		{
			string LibDir = Path.Combine(ThirdPartyPath, "Lib", "Win64");
			PublicAdditionalLibraries.Add(Path.Combine(LibDir, "Loreline.lib"));
			PublicDelayLoadDLLs.Add("Loreline.dll");
			RuntimeDependencies.Add(Path.Combine(LibDir, "Loreline.dll"));
		}
		else if (Target.Platform == UnrealTargetPlatform.Mac)
		{
			string LibDir = Path.Combine(ThirdPartyPath, "Lib", "Mac");
			PublicAdditionalLibraries.Add(Path.Combine(LibDir, "libLoreline.dylib"));
			RuntimeDependencies.Add(Path.Combine(LibDir, "libLoreline.dylib"));
		}
		else if (Target.Platform == UnrealTargetPlatform.Linux)
		{
			string Arch = Target.Architecture == UnrealArch.Arm64 ? "arm64" : "x86_64";
			string LibDir = Path.Combine(ThirdPartyPath, "Lib", "Linux", Arch);
			PublicAdditionalLibraries.Add(Path.Combine(LibDir, "libLoreline.so"));
			RuntimeDependencies.Add(Path.Combine(LibDir, "libLoreline.so"));
		}
		else if (Target.Platform == UnrealTargetPlatform.Android)
		{
			string LibDir = Path.Combine(ThirdPartyPath, "Lib", "Android", "arm64-v8a");
			PublicAdditionalLibraries.Add(Path.Combine(LibDir, "libLoreline.so"));
		}
		else if (Target.Platform == UnrealTargetPlatform.IOS)
		{
			string LibDir = Path.Combine(ThirdPartyPath, "Lib", "IOS");
			PublicAdditionalLibraries.Add(Path.Combine(LibDir, "libLoreline.a"));
		}
	}
}
