#include "LorelineSubsystem.h"
#include "LorelineModule.h"
#include "LorelineScript.h"
#include "Loreline.h"

struct FLorelineFileRequestContext
{
	ULorelineSubsystem* Subsystem;
};

static void OnFileRequestCallback(Loreline_String Path, void (*Provide)(Loreline_String), void* UserData)
{
	FLorelineFileRequestContext* Ctx = static_cast<FLorelineFileRequestContext*>(UserData);
	FString RequestedPath = UTF8_TO_TCHAR(Path.c_str());

	// Check overrides first
	if (FString* Override = Ctx->Subsystem->FileOverrides.Find(RequestedPath))
	{
		Provide(Loreline_String(TCHAR_TO_UTF8(**Override)));
		return;
	}

	// Broadcast event for custom handling
	Ctx->Subsystem->OnFileRequested.Broadcast(RequestedPath);

	// Check overrides again (handler may have called ProvideFile)
	if (FString* Override = Ctx->Subsystem->FileOverrides.Find(RequestedPath))
	{
		Provide(Loreline_String(TCHAR_TO_UTF8(**Override)));
		Ctx->Subsystem->FileOverrides.Remove(RequestedPath);
		return;
	}

	// Try loading from disk
	FString FileContent;
	if (FFileHelper::LoadFileToString(FileContent, *RequestedPath))
	{
		Provide(Loreline_String(TCHAR_TO_UTF8(*FileContent)));
	}
	else
	{
		UE_LOG(LogLoreline, Warning, TEXT("Loreline: Could not load file: %s"), *RequestedPath);
		Provide(Loreline_String());
	}
}

void ULorelineSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);

	Loreline_init();

#if PLATFORM_ANDROID
	Loreline_createThread();
#endif

	TickHandle = FTSTicker::GetCoreTicker().AddTicker(
		FTickerDelegate::CreateUObject(this, &ULorelineSubsystem::Tick));

	UE_LOG(LogLoreline, Log, TEXT("Loreline subsystem initialized"));
}

void ULorelineSubsystem::Deinitialize()
{
	FTSTicker::GetCoreTicker().RemoveTicker(TickHandle);
	Loreline_dispose();

	UE_LOG(LogLoreline, Log, TEXT("Loreline subsystem deinitialized"));

	Super::Deinitialize();
}

bool ULorelineSubsystem::Tick(float DeltaTime)
{
	Loreline_update(static_cast<double>(DeltaTime));
	return true; // Keep ticking
}

ULorelineScript* ULorelineSubsystem::Parse(const FString& SourceCode, const FString& FilePath)
{
	FLorelineFileRequestContext Ctx;
	Ctx.Subsystem = this;

	Loreline_Script* NativeScript = Loreline_parse(
		Loreline_String(TCHAR_TO_UTF8(*SourceCode)),
		Loreline_String(TCHAR_TO_UTF8(*FilePath)),
		OnFileRequestCallback,
		&Ctx);

	if (!NativeScript)
	{
		UE_LOG(LogLoreline, Error, TEXT("Loreline: Failed to parse script"));
		return nullptr;
	}

	ULorelineScript* Script = NewObject<ULorelineScript>(this);
	Script->SetNativeScript(NativeScript);
	return Script;
}

void ULorelineSubsystem::ProvideFile(const FString& Path, const FString& Content)
{
	FileOverrides.Add(Path, Content);
}
