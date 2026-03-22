#pragma once

#include "CoreMinimal.h"
#include "UObject/NoExportTypes.h"
#include "LorelineScript.generated.h"

struct Loreline_Script;
class ULorelineInterpreter;

UCLASS(BlueprintType)
class LORELINE_API ULorelineScript : public UObject
{
	GENERATED_BODY()

public:
	virtual void BeginDestroy() override;

	/** Start playback from a named beat (empty = default). */
	UFUNCTION(BlueprintCallable, Category = "Loreline|Script")
	ULorelineInterpreter* Play(const FString& BeatName = TEXT(""));

	/** Resume playback from saved state. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|Script")
	ULorelineInterpreter* Resume(const FString& SaveData, const FString& BeatName = TEXT(""));

	/** Serialize script to JSON for caching. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|Script")
	FString ToJson(bool bPretty = false) const;

	/** Reconstruct a script from JSON. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|Script", meta = (WorldContext = "WorldContext"))
	static ULorelineScript* FromJson(UObject* WorldContext, const FString& Json);

	/** Debug: print human-readable script representation. */
	UFUNCTION(BlueprintCallable, Category = "Loreline|Script")
	FString PrintScript() const;

	void SetNativeScript(Loreline_Script* InScript) { NativeScript = InScript; }
	Loreline_Script* GetNativeScript() const { return NativeScript; }

private:
	Loreline_Script* NativeScript = nullptr;
};
