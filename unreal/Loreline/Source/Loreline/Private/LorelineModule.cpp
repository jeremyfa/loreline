#include "LorelineModule.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/Paths.h"
#include "HAL/PlatformProcess.h"

DEFINE_LOG_CATEGORY(LogLoreline);

#define LOCTEXT_NAMESPACE "FLorelineModule"

void FLorelineModule::StartupModule()
{
#if PLATFORM_WINDOWS
	FString LibPath = FPaths::Combine(
		IPluginManager::Get().FindPlugin(TEXT("Loreline"))->GetBaseDir(),
		TEXT("Source/ThirdParty/Loreline/Lib/Win64/Loreline.dll"));

	LibraryHandle = FPlatformProcess::GetDllHandle(*LibPath);
	if (!LibraryHandle)
	{
		UE_LOG(LogLoreline, Error, TEXT("Failed to load Loreline.dll from: %s"), *LibPath);
	}
#endif

	UE_LOG(LogLoreline, Log, TEXT("Loreline plugin loaded"));
}

void FLorelineModule::ShutdownModule()
{
	if (LibraryHandle)
	{
		FPlatformProcess::FreeDllHandle(LibraryHandle);
		LibraryHandle = nullptr;
	}

	UE_LOG(LogLoreline, Log, TEXT("Loreline plugin unloaded"));
}

#undef LOCTEXT_NAMESPACE

IMPLEMENT_MODULE(FLorelineModule, Loreline)
