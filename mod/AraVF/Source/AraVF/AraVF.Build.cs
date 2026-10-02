using UnrealBuildTool;

public class AraVF : ModuleRules
{
	public AraVF(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		CppStandard = CppStandardVersion.Cpp20;

		PublicDependencyModuleNames.AddRange(new string[] {
			"Core", "CoreUObject", "Engine",
			"FactoryGame",   // FGMessage, reglages du jeu
			"AkAudio",       // evenements Wwise
			"DummyHeaders",  // en-tetes de substitution du starter project SML
		});
		PrivateDependencyModuleNames.AddRange(new string[] {
			"Projects",      // IPluginManager : recherche des packs de langue
		});
	}
}
