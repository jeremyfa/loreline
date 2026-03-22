#pragma once

#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"
#include "LorelineSubsystem.generated.h"

class ULorelineScript;

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FOnLorelineFileRequested, const FString&, Path);

UCLASS()
class LORELINE_API ULorelineSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;
	virtual void Deinitialize() override;
	virtual bool ShouldCreateSubsystem(UObject* Outer) const override { return true; }

	/** Parse Loreline source code and return a script object. */
	UFUNCTION(BlueprintCallable, Category = "Loreline")
	ULorelineScript* Parse(const FString& SourceCode, const FString& FilePath = TEXT(""));

	/** Provide file content for a pending import request. */
	UFUNCTION(BlueprintCallable, Category = "Loreline")
	void ProvideFile(const FString& Path, const FString& Content);

	/** Fired when a .lor import requests a file. */
	UPROPERTY(BlueprintAssignable, Category = "Loreline|Events")
	FOnLorelineFileRequested OnFileRequested;

private:
	bool Tick(float DeltaTime);
	FTSTicker::FDelegateHandle TickHandle;
	TMap<FString, FString> FileOverrides;
};
